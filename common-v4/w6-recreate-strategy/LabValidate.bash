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

NS=cka4
DEP=proxy
Q4=/root/q4.yaml
LABDIR=/tmp/cka-lab

echo "== w6: Kill the old pods before you make the new ones =="

if ! exists "Deployment $DEP exists in namespace $NS" -n "$NS" deploy "$DEP"; then
  echo; echo -e "${R}w6 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- 1. the update strategy ------------------------------------------------
# The API server refuses a Recreate strategy that still carries a rollingUpdate
# block, so a strategy type of Recreate already proves the block is gone.

STRATEGY=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.strategy.type}' 2>/dev/null)
eq "the update strategy is Recreate" "$STRATEGY" "Recreate"

# ---- 2. the Deployment's own labels ----------------------------------------
CLIENT=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.metadata.labels.client}' 2>/dev/null)
eq "the Deployment itself carries the label client=user" "$CLIENT" "user"

# ---- 3. the pods keep their own labels -------------------------------------

TMPLAPP=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.template.metadata.labels.app}' 2>/dev/null)
eq "the pod template still carries app=proxy" "$TMPLAPP" "proxy"

SELAPP=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.selector.matchLabels.app}' 2>/dev/null)
eq "the Deployment's selector still matches app=proxy" "$SELAPP" "proxy"

LIVEPODS=$(k -n "$NS" get pods -l app=proxy --no-headers 2>/dev/null | grep -c . || true)
if [ "${LIVEPODS:-0}" -ge 1 ] 2>/dev/null; then
  ok "the running pods carry app=proxy ($LIVEPODS pod(s))"
else
  bad "the running pods carry app=proxy (found ${LIVEPODS:-0})"
fi

# ---- the workload itself must be untouched ---------------------------------

REP=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.replicas}' 2>/dev/null)
eq "the Deployment still asks for 6 replicas" "$REP" "6"

IMAGES=""
i=0
while :; do
  CNAME=$(k -n "$NS" get deploy "$DEP" -o jsonpath="{.spec.template.spec.containers[$i].name}" 2>/dev/null)
  [ -n "$CNAME" ] || break
  CIMG=$(k -n "$NS" get deploy "$DEP" -o jsonpath="{.spec.template.spec.containers[$i].image}" 2>/dev/null)
  IMAGES="$IMAGES $CIMG"
  i=$((i+1))
done
has "the containers still run nginx:1.28" "$IMAGES" "nginx:1.28"

READY=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
eq "all 6 replicas are ready" "$READY" "6"

AVAIL=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
eq "all 6 replicas are available" "$AVAIL" "6"

# ---- 4. the Deployment was edited, not replaced -----------------------------

UIDFILE="$LABDIR/w6.dep.uid"
if [ -f "$UIDFILE" ]; then
  OLDUID=$(cat "$UIDFILE" 2>/dev/null)
  NEWUID=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.metadata.uid}' 2>/dev/null)
  if [ -n "$OLDUID" ] && [ -n "$NEWUID" ]; then
    eq "the Deployment was edited in place (same UID)" "$NEWUID" "$OLDUID"
  else
    skip "the recorded or the current Deployment UID is empty - cannot compare them"
  fi
else
  skip "no recorded Deployment UID at $UIDFILE - cannot check that it was edited in place"
fi

# ---- 5. the answer file ----------------------------------------------------

if [ -f "$Q4" ]; then
  ok "$Q4 exists"
  CONTENT=$(cat "$Q4" 2>/dev/null)
  nonempty "$Q4 is not empty" "$CONTENT"

  KINDS=$(k apply --dry-run=client -f "$Q4" -o jsonpath='{.kind}' 2>/dev/null | tr '\n' ' ')
  case "$KINDS" in
    *Deployment*) ok "$Q4 defines a Deployment" ;;
    *) bad "$Q4 defines a Deployment (got kinds: ${KINDS:-<none>})" ;;
  esac

  ERRS=$(k apply --dry-run=client -f "$Q4" -o jsonpath='{.spec.strategy.type}' 2>&1 >/dev/null)
  STRATS=$(k apply --dry-run=client -f "$Q4" -o jsonpath='{.spec.strategy.type}' 2>/dev/null | tr '\n' ' ')
  case "$STRATS" in
    *Recreate*) ok "$Q4 sets the strategy type to Recreate" ;;
    *) bad "$Q4 sets the strategy type to Recreate (got '${STRATS:-<none>}'${ERRS:+ - $ERRS})" ;;
  esac

  case "$CONTENT" in
    *client=user*) note "$Q4 also carries the client=user label" ;;
    *) note "$Q4 does not mention client=user - only the strategy type is graded in the file" ;;
  esac
else
  bad "$Q4 exists (file not found)"
fi

note "Recreate is the strategy that kills the old pods before the new ones are"
note "created. It is the only one that guarantees no two versions of the"
note "workload run at the same time."
note "The labels on a Deployment and on its pod template are different things:"
note "the Deployment's own labels select the Deployment, the template's labels"
note "are what a Service selects on."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}w6 PASSED${X}"; else echo -e "${R}w6 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
