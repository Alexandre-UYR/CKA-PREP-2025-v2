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

NS=diag
POD=web
CM=app-config
LABDIR=/tmp/cka-lab

echo "== x1: The pod that will not start =="

if ! exists "Pod $POD exists in namespace $NS" -n "$NS" pod "$POD"; then
  echo; echo -e "${R}x1 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the Pod is the one that was there at setup ----
ORIG=$(cat "$LABDIR/x1.pod.uid" 2>/dev/null || true)
NOW=$(k -n "$NS" get pod "$POD" -o jsonpath='{.metadata.uid}' 2>/dev/null || true)
if [ -z "$ORIG" ]; then
  bad "the Pod was fixed in place, not re-created (no UID was recorded at setup)"
elif [ "$ORIG" = "$NOW" ]; then
  ok "the Pod was fixed in place, not re-created (its UID is unchanged)"
else
  bad "the Pod was fixed in place, not re-created (its UID changed)"
fi

# ---- the missing piece now exists ----
if exists "ConfigMap $CM exists in namespace $NS" -n "$NS" cm "$CM"; then
  MODE=$(k -n "$NS" get cm "$CM" -o jsonpath='{.data.MODE}' 2>/dev/null)
  eq "the ConfigMap's MODE key is prod" "$MODE" "prod"
else
  bad "ConfigMap $CM exists in namespace $NS"
fi

# ---- the Pod is running ----
PHASE=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null)
eq "the Pod is Running" "$PHASE" "Running"

READY=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
eq "the container is ready" "$READY" "true"

WAITING=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null)
if [ -z "$WAITING" ]; then
  ok "the container is no longer waiting"
else
  bad "the container is no longer waiting (it is waiting on '$WAITING')"
fi

# ---- and the variable really is set inside it ----
VAL=$(k -n "$NS" exec "$POD" -- printenv MODE 2>/dev/null | tr -d '\r\n')
eq "MODE inside the Pod is prod" "$VAL" "prod"

# ---- it did not get there by crashing its way in ----
R1=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
eq "the container has not been restarted" "$R1" "0"

LAST=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}' 2>/dev/null)
if [ "$LAST" = "CreateContainerConfigError" ]; then
  bad "the container never had to fail to start (its last termination was CreateContainerConfigError)"
else
  ok "the container never had to fail to start (last termination: ${LAST:-<none>})"
fi

note "The Pod's status only says the container is WAITING. The reason it is"
note "waiting - and the name of the thing that is missing - is in the Pod's"
note "EVENTS, and in `kubectl describe pod`."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}x1 PASSED${X}"; else echo -e "${R}x1 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
