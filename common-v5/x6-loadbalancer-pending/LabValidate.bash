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
skip(){ echo -e "      SKIP  $1"; }

NS=edge
SVC=public
DEP=site
LABDIR=/tmp/cka-lab
UIDFILE="$LABDIR/x6.svc.uid"
PROBE=cka-live-check
NODEPORT=30080

echo "== x6: The Service that will never get an address =="

if ! exists "namespace $NS exists" namespace "$NS"; then
  echo; echo -e "${R}x6 FAILED ($FAILS checks)${X}"; exit 1
fi

if ! exists "Service $SVC exists in namespace $NS" -n "$NS" svc "$SVC"; then
  echo; echo -e "${R}x6 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the Service is the one that was there at setup ----
ORIG=$(cat "$UIDFILE" 2>/dev/null || true)
NOW=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.metadata.uid}' 2>/dev/null || true)
if [ -z "$ORIG" ]; then
  bad "the Service was edited in place, not replaced (no UID was recorded at setup)"
elif [ "$ORIG" = "$NOW" ]; then
  ok "the Service was edited in place, not replaced (its UID is unchanged)"
else
  bad "the Service was edited in place, not replaced (its UID changed - it was deleted and re-created)"
fi

# ---- the shape of the Service ----
TYPE=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.type}' 2>/dev/null)
eq "the Service's type is NodePort" "$TYPE" "NodePort"

NP=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
eq "the Service's nodePort is $NODEPORT" "$NP" "$NODEPORT"

PORT=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
eq "the Service's port is 80" "$PORT" "80"

TPORT=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)
eq "the Service's targetPort is 80" "$TPORT" "80"

# ---- the selector has to match the pods it selects ----
SEL=$(k -n "$NS" get svc "$SVC" -o go-template='{{range $k, $v := .spec.selector}}{{$k}}={{$v}} {{end}}' 2>/dev/null)
if [ -z "$SEL" ]; then
  bad "the Service still has the selector it had at setup (it has no selector at all)"
else
  for entry in $SEL; do
    KEY=${entry%%=*}
    VAL=${entry#*=}
    PODLABEL=$(k -n "$NS" get deploy "$DEP" -o jsonpath="{.spec.template.metadata.labels.$KEY}" 2>/dev/null)
    if [ "$PODLABEL" = "$VAL" ]; then
      ok "the Service selector '$KEY=$VAL' still matches the pods' labels"
    else
      bad "the Service selector '$KEY=$VAL' still matches the pods' labels (the pods are labelled '$PODLABEL')"
    fi
  done
fi

# ---- the endpoints ----
EP=0
for i in $(seq 1 15); do
  EP=$(k -n "$NS" get endpoints "$SVC" -o jsonpath='{range .subsets[*].addresses[*]}{.ip}{"\n"}{end}' 2>/dev/null | grep -c '[0-9]' || true)
  if [ "${EP:-0}" -ge 2 ] 2>/dev/null; then break; fi
  sleep 2
done
if [ "${EP:-0}" -ge 2 ] 2>/dev/null; then
  ok "the Service has endpoints ($EP endpoint addresses)"
else
  bad "the Service has endpoints (got ${EP:-0}, want at least 2)"
fi

# ---------------------------------------------------------------------------
# Live check: from inside the cluster, reach the Service on the node's IP and
# the nodePort. The node's address is not reachable from a pod on every CNI,
# so a failure there is a SKIP, not a FAIL.
# ---------------------------------------------------------------------------
IPS=$(k get nodes -o jsonpath='{range .items[*]}{range .status.addresses[?(@.type=="InternalIP")]}{.address}{" "}{end}{range .status.addresses[?(@.type=="ExternalIP")]}{.address}{" "}{end}{end}' 2>/dev/null \
      | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u)

run_probe(){
  # Runs one throwaway pod against the given node IP and prints its output.
  local ip=$1
  k -n "$NS" delete pod "$PROBE" --ignore-not-found --wait=true >/dev/null 2>&1
  cat <<EOF | k apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: $PROBE
  namespace: $NS
  labels:
    cka-lab: live-check
spec:
  restartPolicy: Never
  containers:
    - name: probe
      image: busybox:1.36
      command:
        - sh
        - -c
        - |
          wget -S -O /dev/null -T 5 "http://$ip:$NODEPORT/" 2>&1 || true
          if ping -c 1 -W 2 "$ip" >/dev/null 2>&1; then echo "PING=OK"; else echo "PING=FAIL"; fi
EOF
  local phase="" i=0
  while [ "$i" -lt 30 ]; do
    phase=$(k -n "$NS" get pod "$PROBE" -o jsonpath='{.status.phase}' 2>/dev/null)
    case "$phase" in
      Succeeded|Failed) break ;;
    esac
    i=$((i+1)); sleep 2
  done
  local out
  out=$(k -n "$NS" logs "$PROBE" 2>/dev/null)
  k -n "$NS" delete pod "$PROBE" --ignore-not-found --wait=false >/dev/null 2>&1
  printf '%s\n' "$out"
}

LIVE_OK=0
LIVE_REACH=0
LIVE_PROBE_BROKEN=0
LIVE_IP=""
TRIED=0

for ip in $IPS; do
  [ "$TRIED" -ge 3 ] && break
  TRIED=$((TRIED+1))
  OUT=$(run_probe "$ip")
  if [ -z "$OUT" ]; then
    LIVE_PROBE_BROKEN=1
    break
  fi
  CODE=$(printf '%s\n' "$OUT" | grep -o 'HTTP/1\.[01] [0-9][0-9][0-9]' | head -1)
  PING=$(printf '%s\n' "$OUT" | grep -m1 '^PING=' | sed 's/^PING=//' | tr -d '\r')
  case "$CODE" in
    "HTTP/1.1 200"|"HTTP/1.0 200")
      LIVE_OK=1; LIVE_IP=$ip; break ;;
  esac
  if printf '%s\n' "$OUT" | grep -q 'multi-call binary'; then
    # busybox printed its usage: it does not understand the options used
    # here, so the probe itself is broken.
    LIVE_PROBE_BROKEN=1
    break
  fi
  if [ "$PING" = "OK" ]; then
    LIVE_REACH=1
  fi
done

if [ "$LIVE_OK" = "1" ]; then
  ok "a pod inside the cluster reaches the Service on the node's IP ($LIVE_IP):$NODEPORT and gets HTTP 200"
elif [ "$LIVE_PROBE_BROKEN" = "1" ]; then
  skip "the live check could not be run: the probe pod produced no output (it could not be scheduled, or busybox:1.36 could not be pulled)"
elif [ "$LIVE_REACH" = "1" ]; then
  bad "a pod inside the cluster reaches the Service on the node's IP:$NODEPORT and gets HTTP 200 (the node was reachable, but the request did not come back with 200)"
elif [ -z "$IPS" ]; then
  skip "the live check could not be run: the cluster reports no IPv4 address for any node"
else
  skip "the live check could not be run: the node's IPv4 address is not reachable from inside the cluster on this CNI"
fi

note "A LoadBalancer Service stays pending on a cluster that has no"
note "load-balancer implementation - nothing is broken, there is simply"
note "nothing to hand out an address. A NodePort is published on the node's"
note "own IP instead, and that one does answer."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}x6 PASSED${X}"; else echo -e "${R}x6 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
