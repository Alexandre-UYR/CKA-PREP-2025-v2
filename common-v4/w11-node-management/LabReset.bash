#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

LABDIR=/tmp/cka-lab
STATE="$LABDIR/w11.nodes"
TAINT_KEY=dedicated
TAINT_VALUE=payments
TAINT_EFFECT=NoSchedule
LABEL_KEY=Status

# A namespace does not own its nodes: deleting objects in a namespace never
# un-cordons a node or removes a taint. Every node has to be walked
# explicitly.
for n in $(k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
  k uncordon "$n" >/dev/null 2>&1 || true
  k taint node "$n" "$TAINT_KEY=$TAINT_VALUE:$TAINT_EFFECT-" >/dev/null 2>&1 || true
  k label node "$n" "$LABEL_KEY-" >/dev/null 2>&1 || true
done

# The state file is the setup's, not the candidate's, but it goes with the
# rest of the pre-state.
rm -f "$STATE"

echo "w11 reset: every node uncordoned, the $TAINT_KEY=$TAINT_VALUE taint and the"
echo "           $LABEL_KEY label removed from every node, $STATE deleted"
