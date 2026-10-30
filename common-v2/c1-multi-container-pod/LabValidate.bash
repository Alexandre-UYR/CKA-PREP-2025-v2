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

NS=multicontainer
POD=cache

echo "== c1: Multi-container Pod =="

if ! exists "Pod $POD exists in namespace $NS" -n "$NS" pod "$POD"; then
  echo; echo -e "${R}c1 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the two containers ----
NAMES=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null)
eq "the Pod has exactly 2 containers" "$(printf '%s' "$NAMES" | wc -w | tr -d ' ')" "2"
has "a container named redis exists" " $NAMES " " redis "
has "a container named memcached exists" " $NAMES " " memcached "

RIMG=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[?(@.name=="redis")].image}' 2>/dev/null)
has "the redis container uses the redis image" "$RIMG" "redis"

MIMG=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[?(@.name=="memcached")].image}' 2>/dev/null)
has "the memcached container uses the memcached image" "$MIMG" "memcached"

# ---- both containers must be running at the same time ----
for c in redis memcached; do
  READY=$(k -n "$NS" get pod "$POD" -o jsonpath="{.status.containerStatuses[?(@.name==\"$c\")].ready}" 2>/dev/null)
  eq "the $c container is ready" "$READY" "true"
  RUNNING=$(k -n "$NS" get pod "$POD" -o jsonpath="{.status.containerStatuses[?(@.name==\"$c\")].state.running}" 2>/dev/null)
  nonempty "the $c container is running" "$RUNNING"
done

PHASE=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null)
eq "the Pod is Running" "$PHASE" "Running"

# ---- live check: redis actually answers ----
PONG=$(k -n "$NS" exec "$POD" -c redis -- redis-cli ping 2>/dev/null | tr -d '\r\n')
if [ -z "$PONG" ]; then
  bad "the redis container answers a PING (exec into it and run 'redis-cli ping')"
elif [ "$PONG" = "PONG" ]; then
  ok "the redis container answers a PING with PONG"
else
  bad "the redis container answers a PING with PONG (got '$PONG')"
fi

note "A Pod with two containers is only healthy while BOTH are running."
note "If one container exits, the Pod goes to a non-Running phase and the"
note "containers that share the Pod's lifetime go down with it."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c1 PASSED${X}"; else echo -e "${R}c1 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
