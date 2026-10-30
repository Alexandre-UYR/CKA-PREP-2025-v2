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

# Is an IntOrString value greater than zero? "0" and "0%" are zero, "1" and
# "25%" are not.
nonzero(){
  local v="$1" n
  case "$v" in
    '') return 1 ;;
    *%) n="${v%\%}" ;;
    *) n="$v" ;;
  esac
  case "$n" in
    ''|*[!0-9.]*) return 1 ;;
  esac
  [ "$n" -gt 0 ] 2>/dev/null
}

NS=rollout
DEP=web
NEW_IMAGE=nginx:1.26
LABDIR=/tmp/cka-lab

echo "== x17: The rollout that can never move =="

if ! exists "namespace $NS exists" namespace "$NS"; then
  echo; echo -e "${R}x17 FAILED ($FAILS checks)${X}"; exit 1
fi

if ! exists "Deployment $DEP exists in namespace $NS" -n "$NS" deploy "$DEP"; then
  echo; echo -e "${R}x17 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---------------------------------------------------------------------------
# Wait for the rollout to settle before judging it.
# ---------------------------------------------------------------------------
echo "Waiting up to 3 minutes for the rollout to finish..."
i=0
while [ "$i" -lt 180 ]; do
  GEN=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.metadata.generation}' 2>/dev/null)
  OBS=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.observedGeneration}' 2>/dev/null)
  UPD=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.updatedReplicas}' 2>/dev/null)
  REQ=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.replicas}' 2>/dev/null)
  RDY=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  OLD=$(k -n "$NS" get pods -l "app=$DEP" -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' 2>/dev/null | grep -c 'nginx:1\.25' || true)
  PUSED=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.paused}' 2>/dev/null)
  if [ "$UPD" = "$REQ" ] && [ "$REQ" = "3" ] && [ "$RDY" = "3" ] \
     && [ "$GEN" = "$OBS" ] && [ "${OLD:-0}" = "0" ] && [ "$PUSED" != "true" ]; then
    break
  fi
  sleep 5
  i=$((i+5))
done

# ---------------------------------------------------------------------------
# the Deployment is the one that was there at setup: it was edited in place
# ---------------------------------------------------------------------------
ORIG=$(cat "$LABDIR/x17.deploy.uid" 2>/dev/null || true)
NOW=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.metadata.uid}' 2>/dev/null || true)
if [ -z "$ORIG" ]; then
  bad "the Deployment was fixed in place, not re-created (no UID was recorded at setup)"
elif [ "$ORIG" = "$NOW" ]; then
  ok "the Deployment was fixed in place, not re-created (its UID is unchanged)"
else
  bad "the Deployment was fixed in place, not re-created (its UID changed - it was deleted and re-created)"
fi

# ---------------------------------------------------------------------------
# the strategy
# ---------------------------------------------------------------------------
STYPE=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.strategy.type}' 2>/dev/null)
eq "the strategy type is still RollingUpdate" "$STYPE" "RollingUpdate"

SURGE=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.strategy.rollingUpdate.maxSurge}' 2>/dev/null)
UNAVAIL=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.strategy.rollingUpdate.maxUnavailable}' 2>/dev/null)
if nonzero "$SURGE" || nonzero "$UNAVAIL"; then
  ok "the rolling update strategy allows progress (maxSurge '${SURGE:-<unset>}', maxUnavailable '${UNAVAIL:-<unset>}')"
else
  bad "the rolling update strategy allows progress (maxSurge '${SURGE:-<unset>}', maxUnavailable '${UNAVAIL:-<unset>}' - at least one of them has to be greater than zero)"
fi

# ---------------------------------------------------------------------------
# the rollout
# ---------------------------------------------------------------------------
TEMPLATE_IMAGE=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
eq "the pod template asks for $NEW_IMAGE" "$TEMPLATE_IMAGE" "$NEW_IMAGE"

PAUSED=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.paused}' 2>/dev/null)
if [ "$PAUSED" = "true" ]; then
  bad "the Deployment is no longer paused (spec.paused is still true, so the controller will not roll anything out)"
else
  ok "the Deployment is no longer paused"
fi

REPS=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.replicas}' 2>/dev/null)
eq "the Deployment still asks for 3 replicas" "$REPS" "3"

UPD=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.updatedReplicas}' 2>/dev/null)
if [ "$UPD" = "$REPS" ]; then
  ok "every replica is on the new version (updatedReplicas $UPD of $REPS)"
else
  bad "every replica is on the new version (updatedReplicas '$UPD', want '$REPS')"
fi

RDY=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
eq "the Deployment has 3 ready replicas" "$RDY" "3"

GEN=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.metadata.generation}' 2>/dev/null)
OBS=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.observedGeneration}' 2>/dev/null)
if [ -n "$GEN" ] && [ "$GEN" = "$OBS" ]; then
  ok "the rollout has been processed (observedGeneration $OBS = generation $GEN)"
else
  bad "the rollout has been processed (observedGeneration '$OBS', generation '$GEN')"
fi

OLD=$(k -n "$NS" get pods -l "app=$DEP" -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' 2>/dev/null | grep -c 'nginx:1\.25' || true)
if [ "${OLD:-0}" = "0" ]; then
  ok "no pod of the Deployment is left on nginx:1.25"
else
  bad "no pod of the Deployment is left on nginx:1.25 ($OLD pod(s) still on it)"
fi

note "maxSurge is how many pods MAY be created above the desired count, and"
note "maxUnavailable is how many may be unavailable. With BOTH at zero the controller"
note "is not allowed to create the new pod and not allowed to delete the old one, so"
note "the rollout is deadlocked. A rolling update needs one of the two to be non-zero."
note "The API server will not let you set them both to zero, though:"
note '  spec.strategy.rollingUpdate.maxUnavailable: Invalid value: 0: may not be 0 when `maxSurge` is 0'

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}x17 PASSED${X}"; else echo -e "${R}x17 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
