#!/bin/bash
set -uo pipefail

# Byte-wise string comparison for the timestamps below, so that the order of
# two RFC3339 times does not depend on the locale.
LC_ALL=C
export LC_ALL

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
skip(){ echo -e "      SKIP  $1"; }

NS=dns
NS_SYS=kube-system
LABDIR=/tmp/cka-lab
CLUSTER_NAME=kubernetes.default.svc.cluster.local
EXT_NAME=example.com

echo "== x8: Cluster names work, the internet does not =="

if ! exists "namespace $NS exists" namespace "$NS"; then
  echo; echo -e "${R}x8 FAILED ($FAILS checks)${X}"; exit 1
fi

# --- find CoreDNS, by name or by label ---
CM_NAME="coredns"
k -n "$NS_SYS" get configmap "$CM_NAME" >/dev/null 2>&1 || \
  CM_NAME=$(k -n "$NS_SYS" get configmap -l k8s-app=kube-dns -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
DEP_NAME="coredns"
k -n "$NS_SYS" get deployment "$DEP_NAME" >/dev/null 2>&1 || \
  DEP_NAME=$(k -n "$NS_SYS" get deployment -l k8s-app=kube-dns -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [ -z "$CM_NAME" ] || [ -z "$DEP_NAME" ]; then
  bad "CoreDNS was found in $NS_SYS (no ConfigMap and Deployment to check)"
  echo; echo -e "${R}x8 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---------------------------------------------------------------------------
# 1. The Corefile has to forward again.
# ---------------------------------------------------------------------------
COREFILE=$(k -n "$NS_SYS" get configmap "$CM_NAME" -o jsonpath='{.data.Corefile}' 2>/dev/null)
if [ -z "$COREFILE" ]; then
  bad "the CoreDNS ConfigMap $CM_NAME has a Corefile (got nothing)"
  FWD=""
else
  ok "the CoreDNS ConfigMap $CM_NAME has a Corefile"
  FWD=$(printf '%s\n' "$COREFILE" | grep -E '^[[:space:]]*forward[[:space:]]+\.[[:space:]]+[^[:space:]]+' | head -1)
  if [ -n "$FWD" ]; then
    ok "the Corefile has a forward directive ('$(printf '%s' "$FWD" | tr -s ' ' | sed 's/^ //')')"
  else
    bad "the Corefile has a forward directive (got none - the Corefile is '$(printf '%s' "$COREFILE" | tr '\n' ' | ')')"
  fi
fi

case "$COREFILE" in
  *kubernetes*) note "the Corefile still names the kubernetes plugin, so cluster names keep working";;
  *) note "the Corefile does not name the kubernetes plugin - cluster service names will not resolve either";;
esac

# ---------------------------------------------------------------------------
# 2. CoreDNS has to be running.
# ---------------------------------------------------------------------------
k -n "$NS_SYS" rollout status "deploy/$DEP_NAME" --timeout=120s >/dev/null 2>&1 || true

READY=$(k -n "$NS_SYS" get deploy "$DEP_NAME" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
case "$READY" in ''|*[!0-9]*) READY=0;; esac
if [ "${READY:-0}" -ge 1 ]; then
  ok "the CoreDNS Deployment has at least 1 ready replica"
else
  bad "the CoreDNS Deployment has at least 1 ready replica (got '${READY:-0}')"
fi

# ---------------------------------------------------------------------------
# 3. CoreDNS has to have been restarted AFTER the ConfigMap was changed.
#
# CoreDNS parses its Corefile when the process starts, so a ConfigMap change
# on its own does nothing. The evidence is the pod's start time compared with
# the ConfigMap's last write time. The `kubectl.kubernetes.io/restartedAt`
# annotation that `rollout restart` adds to the pod template is accepted as
# well.
# ---------------------------------------------------------------------------
norm_time(){ printf '%s' "$1" | sed 's/\.[0-9]*//; s/+00:00$/Z/'; }
ts_ge(){
  # $1 >= $2, compared byte-wise. There is no string >= operator in test, so
  # equality is checked separately.
  if [ "$1" = "$2" ]; then return 0; fi
  if [ "$1" \> "$2" ]; then return 0; fi
  return 1
}

CM_TIME=""
for t in $(k -n "$NS_SYS" get configmap "$CM_NAME" -o jsonpath='{range .metadata.managedFields[*]}{.time}{"\n"}{end}' 2>/dev/null); do
  t=$(norm_time "$t")
  case "$t" in
    [0-9][0-9][0-9][0-9]-*)
      if [ -z "$CM_TIME" ] || [ "$t" \> "$CM_TIME" ]; then CM_TIME="$t"; fi ;;
  esac
done

PODSEL=$(k -n "$NS_SYS" get deploy "$DEP_NAME" -o go-template='{{range $k, $v := .spec.selector.matchLabels}}{{$k}}={{$v}},{{end}}' 2>/dev/null || true)
PODSEL=$(printf '%s' "$PODSEL" | sed 's/,$//')
if [ -z "$PODSEL" ]; then PODSEL="k8s-app=kube-dns"; fi

PSTART=$(k -n "$NS_SYS" get pods -l "$PODSEL" -o jsonpath='{range .items[*]}{.status.startTime}{"\n"}{end}' 2>/dev/null | grep -v '^[[:space:]]*$' | sort | tail -n 1)
RA=$(k -n "$NS_SYS" get deploy "$DEP_NAME" -o jsonpath='{.spec.template.metadata.annotations.kubectl\.kubernetes\.io/restartedAt}' 2>/dev/null)

RESTART_OK=0
RESTART_WHY=""
if [ -n "$CM_TIME" ] && [ -n "$PSTART" ]; then
  if ts_ge "$PSTART" "$CM_TIME"; then
    RESTART_OK=1
    RESTART_WHY="the CoreDNS pod started at $PSTART, at or after the ConfigMap was last written at $CM_TIME"
  fi
fi
if [ "$RESTART_OK" -eq 0 ] && [ -n "$RA" ]; then
  RAN=$(norm_time "$RA")
  if [ -z "$CM_TIME" ] || ts_ge "$RAN" "$CM_TIME"; then
    RESTART_OK=1
    RESTART_WHY="the pod template carries kubectl.kubernetes.io/restartedAt=$RA"
  fi
fi

if [ "$RESTART_OK" = "1" ]; then
  ok "CoreDNS was restarted after the ConfigMap was changed ($RESTART_WHY)"
elif [ -z "$CM_TIME" ]; then
  bad "CoreDNS was restarted after the ConfigMap was changed (the ConfigMap's last write time could not be read, and the pod template has no kubectl.kubernetes.io/restartedAt annotation)"
elif [ -z "$PSTART" ]; then
  bad "CoreDNS was restarted after the ConfigMap was changed (no running CoreDNS pod was found, so nothing is serving the new Corefile)"
else
  bad "CoreDNS was restarted after the ConfigMap was changed (the pod started at $PSTART, which is before the ConfigMap was last written at $CM_TIME - restart it with 'kubectl -n $NS_SYS rollout restart deploy/$DEP_NAME')"
fi

# ---------------------------------------------------------------------------
# 4. Live check: a pod resolves a cluster service name.
# ---------------------------------------------------------------------------
probe(){
  # $1 pod name, $2 name to look up, $3 dnsPolicy
  local pod=$1 name=$2 policy=$3
  k -n "$NS" delete pod "$pod" --ignore-not-found --wait=true >/dev/null 2>&1
  cat <<EOF | k apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: $pod
  namespace: $NS
  labels:
    cka-lab: live-check
spec:
  restartPolicy: Never
  dnsPolicy: $policy
  containers:
    - name: probe
      image: busybox:1.36
      command:
        - sh
        - -c
        - nslookup $name 2>&1 || true
EOF
  local phase="" i=0
  while [ "$i" -lt 30 ]; do
    phase=$(k -n "$NS" get pod "$pod" -o jsonpath='{.status.phase}' 2>/dev/null)
    case "$phase" in
      Succeeded|Failed) break ;;
    esac
    i=$((i+1)); sleep 2
  done
  local out
  out=$(k -n "$NS" logs "$pod" 2>/dev/null)
  k -n "$NS" delete pod "$pod" --ignore-not-found --wait=false >/dev/null 2>&1
  printf '%s\n' "$out"
}

resolved(){
  # $1 = nslookup output
  printf '%s\n' "$1" | grep -E '^Address:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*$' >/dev/null 2>&1
}

INTERNAL_OUT=$(probe x8probe "$CLUSTER_NAME" ClusterFirst)
if resolved "$INTERNAL_OUT"; then
  ok "a pod in namespace $NS resolves $CLUSTER_NAME"
elif [ -z "$INTERNAL_OUT" ]; then
  bad "a pod in namespace $NS resolves $CLUSTER_NAME (the probe pod produced no output - it could not be scheduled, or busybox:1.36 could not be pulled)"
else
  bad "a pod in namespace $NS resolves $CLUSTER_NAME (nslookup reported: '$(printf '%s' "$INTERNAL_OUT" | tr '\n' ' | ')')"
fi

# ---------------------------------------------------------------------------
# 5. Live check: a pod resolves an external name.
#
# When the cluster's own resolver cannot reach the outside either, this is an
# environment problem rather than an answer problem, so it is skipped with a
# reason. A pod that uses the node's resolver directly is the fair
# comparison: CoreDNS forwards to exactly that resolver.
# ---------------------------------------------------------------------------
EXT_OUT=$(probe x8probe "$EXT_NAME" ClusterFirst)
if resolved "$EXT_OUT"; then
  ok "a pod in namespace $NS resolves $EXT_NAME"
else
  UPSTREAM_OUT=$(probe x8probe "$EXT_NAME" Default)
  if resolved "$UPSTREAM_OUT"; then
    bad "a pod in namespace $NS resolves $EXT_NAME (the node's own resolver resolves $EXT_NAME, so the cluster CAN do it - CoreDNS is not forwarding)"
  else
    skip "the external name check could not be run: the node's own resolver cannot resolve $EXT_NAME either, so this cluster has no outbound DNS to forward to"
  fi
fi

note "The kubernetes plugin serves the names inside the cluster. The forward"
note "plugin sends everything else to the node's resolver. Removing one"
note "leaves the other working, which is why the symptom is so specific."
note "And CoreDNS reads its Corefile at start-up, so the Deployment has to"
note "be restarted for a ConfigMap change to take effect."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}x8 PASSED${X}"; else echo -e "${R}x8 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
