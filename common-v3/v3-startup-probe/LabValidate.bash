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

NS=probe
DEP=slow

echo "== v3: The app that is killed before it starts =="

if ! exists "Deployment $DEP exists in namespace $NS" -n "$NS" deploy "$DEP"; then
  echo; echo -e "${R}v3 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the startup probe ----
SP=$(k -n "$NS" get deploy "$DEP" \
     -o jsonpath='{.spec.template.spec.containers[0].startupProbe}' 2>/dev/null)
nonempty "the container has a startupProbe" "$SP"

SPEXEC=$(k -n "$NS" get deploy "$DEP" \
         -o jsonpath='{.spec.template.spec.containers[0].startupProbe.exec.command}' 2>/dev/null)
SPHTTP=$(k -n "$NS" get deploy "$DEP" \
         -o jsonpath='{.spec.template.spec.containers[0].startupProbe.httpGet.path}' 2>/dev/null)
SPPORT=$(k -n "$NS" get deploy "$DEP" \
         -o jsonpath='{.spec.template.spec.containers[0].startupProbe.httpGet.port}' 2>/dev/null)
if [ -n "$SPEXEC" ] || { [ -n "$SPHTTP" ] && [ -n "$SPPORT" ]; }; then
  ok "the startupProbe is an exec or an httpGet probe"
else
  bad "the startupProbe is an exec or an httpGet probe (exec '$SPEXEC', httpGet '$SPHTTP:$SPPORT')"
fi

FT=$(k -n "$NS" get deploy "$DEP" \
     -o jsonpath='{.spec.template.spec.containers[0].startupProbe.failureThreshold}' 2>/dev/null)
PS=$(k -n "$NS" get deploy "$DEP" \
     -o jsonpath='{.spec.template.spec.containers[0].startupProbe.periodSeconds}' 2>/dev/null)
ID=$(k -n "$NS" get deploy "$DEP" \
     -o jsonpath='{.spec.template.spec.containers[0].startupProbe.initialDelaySeconds}' 2>/dev/null)
[ -z "$FT" ] && FT=3
[ -z "$PS" ] && PS=10
[ -z "$ID" ] && ID=0
BUDGET=$(( FT * PS ))
if [ "$BUDGET" -ge 60 ]; then
  ok "the startupProbe budget covers the 60-second start-up (failureThreshold $FT x periodSeconds $PS = ${BUDGET}s, initialDelaySeconds $ID)"
else
  bad "the startupProbe budget covers the 60-second start-up (failureThreshold $FT x periodSeconds $PS = ${BUDGET}s, need at least 60s)"
fi

# ---- the application itself must not be watered down to make the probes pass ----
CMD=$(k -n "$NS" get deploy "$DEP" \
      -o jsonpath='{.spec.template.spec.containers[0].command}' 2>/dev/null)
case "$CMD" in
  *"sleep 60"*) ok "the app still has its 60-second start-up";;
  *) bad "the app still has its 60-second start-up (command '$CMD')";;
esac

# ---- the pod ----
echo "Waiting for the pod to become Ready..."
POD=""
READY=""
i=0
while [ "$i" -lt 180 ]; do
  POD=$(k -n "$NS" get pods -l "app=$DEP" --sort-by=.metadata.creationTimestamp \
        -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
        | tr -d '\r' | grep -v '^[[:space:]]*$' | tail -1)
  if [ -n "$POD" ]; then
    READY=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
    [ "$READY" = "true" ] && break
  fi
  sleep 5
  i=$((i+5))
done

if [ -n "$POD" ]; then
  ok "the pod is $POD"
  PHASE=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null)
  eq "the pod is Running" "$PHASE" "Running"
  eq "the container is ready" "$READY" "true"
else
  bad "a pod exists for the $DEP deployment"
fi

# ---- and it stays up ----
if [ -n "$POD" ]; then
  R1=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
  echo "Sampling the restart count twice, 25 seconds apart..."
  sleep 25
  R2=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
  if [ -n "$R1" ] && [ "$R1" = "$R2" ]; then
    ok "the restart count has stopped climbing (it stayed at $R1)"
  else
    bad "the restart count has stopped climbing (it went from '$R1' to '$R2')"
  fi
else
  skip "the restart count check (there is no pod to sample)"
fi

note "A startupProbe gates the liveness and readiness probes: while it has not"
note "succeeded, the liveness probe is not evaluated at all. The budget is"
note "failureThreshold x periodSeconds, and it has to cover the start-up time."
note "The window above is 25 seconds because the old liveness probe kills the"
note "container about 15 seconds after it starts - a 10 second sample could"
note "miss the kill entirely."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}v3 PASSED${X}"; else echo -e "${R}v3 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
