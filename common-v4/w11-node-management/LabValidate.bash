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

LABDIR=/tmp/cka-lab
STATE="$LABDIR/w11.nodes"
TAINT_KEY=dedicated
TAINT_VALUE=payments
TAINT_EFFECT=NoSchedule
LABEL_KEY=Status
LABEL_VALUE=VIP

echo "== w11: Bring the nodes back =="

# ---- which node was which ---------------------------------------------------
# The setup recorded it. The cluster cannot say any more, once the taint has
# been removed.
if [ ! -f "$STATE" ]; then
  bad "the setup's state file $STATE is there (the validator cannot tell which node was cordoned and which was tainted)"
  echo; echo -e "${R}w11 FAILED ($FAILS checks)${X}"; exit 1
fi

CORDONED=$(sed -n 's/^CORDONED=//p' "$STATE" 2>/dev/null | head -1)
TAINTED=$(sed -n 's/^TAINTED=//p' "$STATE" 2>/dev/null | head -1)

if [ -z "$CORDONED" ] || [ -z "$TAINTED" ]; then
  bad "the setup's state file $STATE names both nodes"
  echo; echo -e "${R}w11 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- 1. the cordoned node is schedulable again ------------------------------
if ! k get node "$CORDONED" >/dev/null 2>&1; then
  bad "the node $CORDONED that was cordoned still exists"
else
  ok "the node $CORDONED that was cordoned still exists"
  UNSCHED=$(k get node "$CORDONED" -o jsonpath='{.spec.unschedulable}' 2>/dev/null)
  if [ -z "$UNSCHED" ] || [ "$UNSCHED" = "false" ]; then
    ok "the node $CORDONED is schedulable again (unschedulable is ${UNSCHED:-absent})"
  else
    bad "the node $CORDONED is schedulable again (got unschedulable=$UNSCHED)"
  fi
fi

# ---- 2. no node carries the taint -------------------------------------------
TAINTED_COUNT=0
TAINTED_ON=""
for n in $(k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
  KT=$(k get node "$n" \
        -o jsonpath='{range .spec.taints[?(@.key=="dedicated")]}{.value}:{.effect}{"\n"}{end}' 2>/dev/null)
  # Any taint with this key and this value counts, whatever its effect: the
  # task asks for the taint to be gone, not for it to be re-worded.
  case "$KT" in
    "$TAINT_VALUE":*)
      TAINTED_COUNT=$((TAINTED_COUNT+1))
      TAINTED_ON="$TAINTED_ON $n"
      ;;
  esac
done
eq "no node carries the $TAINT_KEY=$TAINT_VALUE taint" "$TAINTED_COUNT" "0"

# ---- 3. the label ------------------------------------------------------------
VC=$(k get nodes -l "$LABEL_KEY=$LABEL_VALUE" -o name 2>/dev/null | grep -c 'node/' || true)
eq "exactly one node carries the label $LABEL_KEY=$LABEL_VALUE" "${VC:-0}" "1"

VN=$(k get nodes -l "$LABEL_KEY=$LABEL_VALUE" \
      -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -1)
eq "the $LABEL_KEY=$LABEL_VALUE label is on the node that carried the taint" "$VN" "$TAINTED"

# ---- 4. the selector works ---------------------------------------------------
LSEL=$(k get nodes -l "$LABEL_KEY=$LABEL_VALUE" 2>&1 \
        | grep -v 'No resources found' \
        | grep -v '^error' \
        | grep -c '[^[:space:]]' || true)
eq "kubectl get nodes -l $LABEL_KEY=$LABEL_VALUE returns exactly one line" "${LSEL:-0}" "1"

note "Cordoning and tainting are different things. 'unschedulable' is a flag on"
note "the node: the scheduler honours it for NEW pods, and it evicts nothing."
note "A taint is a property ordinary pods must actively tolerate, and"
note "NoSchedule keeps new pods away without evicting either."
note "Draining is a third thing, and it evicts."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}w11 PASSED${X}"; else echo -e "${R}w11 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
