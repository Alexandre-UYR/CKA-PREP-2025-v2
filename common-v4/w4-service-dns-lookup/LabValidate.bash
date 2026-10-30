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

NS=dns-demo
REDPOD=redis
SVC=redis-svc
LOOKER=looker
ANSWER=/root/q5.txt

echo "== w4: The name that does not resolve =="

# How many endpoint addresses a Service has right now.
ep_count(){
  k -n "$NS" get endpoints "$1" \
    -o jsonpath='{range .subsets[*].addresses[*]}{.ip}{"\n"}{end}' 2>/dev/null \
    | grep -c '[0-9]' || true
}

# The endpoints controller reacts to a selector change asynchronously, so give
# it a moment before deciding that a Service has no endpoints.
wait_ep(){
  local svc=$1 min=$2 n=0 c=0
  while [ "$n" -lt 60 ]; do
    c=$(ep_count "$svc")
    if [ "${c:-0}" -ge "$min" ]; then
      break
    fi
    sleep 2
    n=$((n+2))
  done
  echo "${c:-0}"
}

# ---- the pre-state ---------------------------------------------------------

exists "Service $SVC exists in namespace $NS" -n "$NS" svc "$SVC"
exists "Pod $REDPOD exists in namespace $NS" -n "$NS" pod "$REDPOD"

PHASE=$(k -n "$NS" get pod "$REDPOD" -o jsonpath='{.status.phase}' 2>/dev/null || true)
eq "the Pod $REDPOD is Running" "$PHASE" "Running"

LOOKPHASE=$(k -n "$NS" get pod "$LOOKER" -o jsonpath='{.status.phase}' 2>/dev/null || true)
eq "the Pod $LOOKER is Running" "$LOOKPHASE" "Running"

# ---- 1. the Service is repaired -------------------------------------------

PODLABEL=$(k -n "$NS" get pod "$REDPOD" -o jsonpath='{.metadata.labels.app}' 2>/dev/null || true)
eq "the Pod $REDPOD carries the label app=redis" "$PODLABEL" "redis"

SEL=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.selector.app}' 2>/dev/null || true)
eq "the Service $SVC selects app=redis" "$SEL" "redis"

eq "the Service $SVC listens on port 11211" \
  "$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)" "11211"
eq "the Service $SVC targets port 11211" \
  "$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)" "11211"

# ---- 2. the Service has endpoints -----------------------------------------

C=$(wait_ep "$SVC" 1)
if [ "${C:-0}" -ge 1 ]; then
  ok "the Service $SVC has an endpoint address ($C)"
else
  bad "the Service $SVC has an endpoint address (got ${C:-0}, want at least 1)"
fi

# ---- the live check: nslookup from the looker pod -------------------------

CLUSTERIP=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
PODIP=$(k -n "$NS" get pod "$REDPOD" -o jsonpath='{.status.podIP}' 2>/dev/null || true)

nonempty "the Service $SVC has a ClusterIP" "$CLUSTERIP"
nonempty "the Pod $REDPOD has a Pod IP" "$PODIP"

if [ "$LOOKPHASE" = "Running" ]; then
  OUT=$(k -n "$NS" exec "$LOOKER" -- nslookup "$SVC" 2>&1 || true)
  if [ -n "$OUT" ]; then
    ok "nslookup ran in the $LOOKER pod"
  else
    bad "nslookup ran in the $LOOKER pod (it returned nothing)"
  fi
  has "nslookup $SVC from the $LOOKER pod returns the Service ClusterIP $CLUSTERIP" \
    "$OUT" "$CLUSTERIP"
else
  skip "the live nslookup check (the $LOOKER pod is not Running)"
fi

# ---- 3. the answer file ---------------------------------------------------

if [ -f "$ANSWER" ]; then
  ok "$ANSWER exists"
  CONTENT=$(cat "$ANSWER" 2>/dev/null)
  nonempty "$ANSWER is not empty" "$CONTENT"
  LINES=$(sed '/^[[:space:]]*$/d' "$ANSWER" 2>/dev/null | wc -l | tr -d ' ')
  eq "$ANSWER has two lines" "$LINES" "2"
  has "$ANSWER contains the Service ClusterIP $CLUSTERIP" "$CONTENT" "$CLUSTERIP"
  has "$ANSWER contains the Pod IP $PODIP" "$CONTENT" "$PODIP"
else
  bad "$ANSWER exists (file not found)"
fi

note "A Service's name resolves to its ClusterIP through CoreDNS, whatever"
note "its selector says. A Service that matches nothing still resolves - it"
note "just resolves to an address with nothing behind it, which is why the"
note "name resolving is not the same as the Service working."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}w4 PASSED${X}"; else echo -e "${R}w4 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
