#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }
G='\033[32m'; R='\033[31m'; X='\033[0m'
FAILS=0
ok(){ echo -e "${G}PASS${X}  $1"; }
bad(){ echo -e "${R}FAIL${X}  $1"; FAILS=$((FAILS+1)); }
eq(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }
has(){ case "$2" in *"$3"*) ok "$1";; *) bad "$1 (got '$2')";; esac; }
nonempty(){ if [ -n "$2" ]; then ok "$1"; else bad "$1"; fi; }
exists(){ local d=$1; shift; if k get "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
note(){ echo -e "      NOTE  $1"; }

echo "== Q8 CNI & Network Policy =="

TESTNS=cka-q8-test

cleanup(){
  k delete ns "$TESTNS" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ---- requirement: a CNI installed from a manifest ----
# Flannel does not implement NetworkPolicy, so the only acceptable answer is Calico.
if exists "Calico CRD crd.projectcalico.org is installed" crd crd.projectcalico.org; then :; else
  echo -e "      HINT  Flannel cannot satisfy this question - it has no NetworkPolicy implementation."
fi
exists "the tigera-operator deployment is running" -n tigera-operator deploy tigera-operator
exists "the calico-node DaemonSet is installed" -n kube-system ds calico-node

if k -n kube-system get ds kube-flannel >/dev/null 2>&1; then
  note "kube-flannel is also present. It does not implement NetworkPolicy, so Calico is what satisfies requirement 2."
fi

NODES=$(k get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
CALREADY=$(k -n kube-system get ds calico-node -o jsonpath='{.status.numberReady}' 2>/dev/null)
if [ -n "$NODES" ] && [ "$NODES" != "0" ]; then
  eq "calico-node is ready on every node" "$CALREADY" "$NODES"
else
  bad "could not count the nodes in the cluster"
fi

# ---- requirement 1: pods can talk to each other ----
echo
echo "Testing pod-to-pod connectivity (pulls nginx:alpine, may take ~30s)..."
cleanup
k create ns "$TESTNS" >/dev/null 2>&1
k -n "$TESTNS" run target --image=nginx:alpine --restart=Never >/dev/null 2>&1
if k -n "$TESTNS" wait --for=condition=Ready pod/target --timeout=120s >/dev/null 2>&1; then
  TIP=$(k -n "$TESTNS" get pod target -o jsonpath='{.status.podIP}' 2>/dev/null)
  if [ -n "$TIP" ]; then
    if k -n "$TESTNS" run client --rm -i --restart=Never --image=nginx:alpine \
        -- wget -q -T 5 -O /dev/null "http://$TIP" >/dev/null 2>&1; then
      ok "pods can communicate with each other"
    else
      bad "pods cannot communicate with each other (the CNI is not carrying pod traffic)"
    fi
  else
    bad "the test pod never got an IP"
  fi
else
  bad "the test pod never became Ready, so connectivity could not be tested"
fi

# ---- requirement 2: NetworkPolicy is actually enforced ----
echo
echo "Testing NetworkPolicy enforcement..."
cleanup
k create ns "$TESTNS" >/dev/null 2>&1
cat <<EOF | k apply -f - >/dev/null 2>&1
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: $TESTNS
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF
sleep 10
k -n "$TESTNS" run target --image=nginx:alpine --restart=Never >/dev/null 2>&1
if k -n "$TESTNS" wait --for=condition=Ready pod/target --timeout=120s >/dev/null 2>&1; then
  TIP=$(k -n "$TESTNS" get pod target -o jsonpath='{.status.podIP}' 2>/dev/null)
  if k -n "$TESTNS" run client --rm -i --restart=Never --image=nginx:alpine \
      -- wget -q -T 5 -O /dev/null "http://$TIP" >/dev/null 2>&1; then
    bad "traffic still flows with a deny-all policy in place - NetworkPolicy is NOT being enforced"
  else
    ok "NetworkPolicy is enforced (traffic is blocked by the deny-all policy)"
  fi
else
  bad "the test pod never became Ready, so NetworkPolicy enforcement could not be tested"
fi

cleanup
trap - EXIT

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}Q8 PASSED${X}"; else echo -e "${R}Q8 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
