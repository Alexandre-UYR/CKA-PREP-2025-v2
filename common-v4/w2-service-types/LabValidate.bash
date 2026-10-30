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

NS=svcs
DEP=web
CIPSVC=web-clusterip
NPSVC=web-nodeport
LBSVC=web-lb

echo "== w2: Three Services, one of them broken =="

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

exists "Deployment $DEP exists in namespace $NS" -n "$NS" deploy "$DEP"
exists "Service $CIPSVC exists in namespace $NS" -n "$NS" svc "$CIPSVC"

# ---- 1/2. the broken Service was repaired, not replaced --------------------

ORIG=$(k -n "$NS" get namespace "$NS" \
        -o go-template='{{index .metadata.annotations "cka-lab/original-service"}}' 2>/dev/null || true)
CUR=$(k -n "$NS" get svc "$CIPSVC" -o jsonpath='{.metadata.uid}' 2>/dev/null || true)
if [ -z "$ORIG" ]; then
  skip "the Service $CIPSVC was fixed in place (the setup did not record its UID)"
else
  eq "$CIPSVC was fixed in place, not deleted and re-created" "$CUR" "$ORIG"
fi

eq "Service $CIPSVC is of type ClusterIP" \
  "$(k -n "$NS" get svc "$CIPSVC" -o jsonpath='{.spec.type}' 2>/dev/null)" "ClusterIP"
eq "Service $CIPSVC listens on port 80" \
  "$(k -n "$NS" get svc "$CIPSVC" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)" "80"
eq "Service $CIPSVC targets port 80" \
  "$(k -n "$NS" get svc "$CIPSVC" -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)" "80"

# ---- 3. the two new Services ----------------------------------------------

exists "Service $NPSVC exists in namespace $NS" -n "$NS" svc "$NPSVC"
exists "Service $LBSVC exists in namespace $NS" -n "$NS" svc "$LBSVC"

eq "Service $NPSVC is of type NodePort" \
  "$(k -n "$NS" get svc "$NPSVC" -o jsonpath='{.spec.type}' 2>/dev/null)" "NodePort"
eq "Service $NPSVC listens on port 80" \
  "$(k -n "$NS" get svc "$NPSVC" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)" "80"
eq "Service $NPSVC targets port 80" \
  "$(k -n "$NS" get svc "$NPSVC" -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)" "80"
eq "Service $NPSVC uses nodePort 30080" \
  "$(k -n "$NS" get svc "$NPSVC" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)" "30080"

eq "Service $LBSVC is of type LoadBalancer" \
  "$(k -n "$NS" get svc "$LBSVC" -o jsonpath='{.spec.type}' 2>/dev/null)" "LoadBalancer"
eq "Service $LBSVC listens on port 80" \
  "$(k -n "$NS" get svc "$LBSVC" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)" "80"
eq "Service $LBSVC targets port 80" \
  "$(k -n "$NS" get svc "$LBSVC" -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)" "80"

# ---- 4. all three select the pods -----------------------------------------

PODAPP=$(k -n "$NS" get pods -l "app=$DEP" \
          -o jsonpath='{.items[0].metadata.labels.app}' 2>/dev/null || true)
eq "the Deployment's pods carry the label app=$DEP" "$PODAPP" "$DEP"

for s in $CIPSVC $NPSVC $LBSVC; do
  SEL=$(k -n "$NS" get svc "$s" -o jsonpath='{.spec.selector.app}' 2>/dev/null || true)
  eq "Service $s selects app=$DEP" "$SEL" "$DEP"
done

for s in $CIPSVC $NPSVC $LBSVC; do
  C=$(wait_ep "$s" 2)
  if [ "${C:-0}" -ge 2 ]; then
    ok "Service $s has endpoints ($C addresses)"
  else
    bad "Service $s has endpoints (got ${C:-0}, want at least 2)"
  fi
done

note "A Service's selector is the only thing that decides which pods it"
note "points at. The Service object itself can look entirely correct while"
note "resolving to nothing at all."
note "The LoadBalancer's EXTERNAL-IP is NOT graded: on a cluster with no"
note "load-balancer implementation it stays <pending> for ever, and that is"
note "an environment limit rather than a wrong answer."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}w2 PASSED${X}"; else echo -e "${R}w2 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
