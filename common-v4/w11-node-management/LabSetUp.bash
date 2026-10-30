#!/bin/bash
set -e

# w11 - Bring the nodes back
#
# The pre-state is two nodes that refuse new pods for different reasons:
#
#   node A  cordoned, so it will not take new pods
#   node B  tainted dedicated=payments:NoSchedule
#
# The setup puts both nodes back first - uncordon, untaint, clear the label -
# so a second run starts from exactly the same state as the first. The names
# of the two nodes are recorded in /tmp/cka-lab/w11.nodes, because once the
# taint is gone the cluster no longer says which node carried it.

LABDIR=/tmp/cka-lab
STATE="$LABDIR/w11.nodes"
TAINT_KEY=dedicated
TAINT_VALUE=payments
TAINT_EFFECT=NoSchedule
LABEL_KEY=Status
LABEL_VALUE=VIP

mkdir -p "$LABDIR"

is_control_plane(){
  kubectl get node "$1" -o jsonpath='{.metadata.labels}' 2>/dev/null \
    | grep -Eq 'node-role\.kubernetes\.io/(control-plane|master)'
}

is_ready(){
  [ "$(kubectl get node "$1" -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status}{end}' 2>/dev/null)" = "True" ]
}

nth(){
  # $1 = space separated list, $2 = 1-based index
  echo "$1" | tr ' ' '\n' | sed -n "${2}p"
}

ALL_NODES=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)
if [ -z "$ALL_NODES" ]; then
  echo "This cluster reports no nodes at all. Nothing to set up." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Undo whatever a previous attempt left behind, on every node
# ---------------------------------------------------------------------------

for n in $ALL_NODES; do
  kubectl uncordon "$n" >/dev/null 2>&1 || true
  kubectl taint node "$n" "$TAINT_KEY=$TAINT_VALUE:$TAINT_EFFECT-" >/dev/null 2>&1 || true
  kubectl label node "$n" "$LABEL_KEY-" >/dev/null 2>&1 || true
done

# ---------------------------------------------------------------------------
# Pick the two nodes the pre-state needs
# ---------------------------------------------------------------------------

READY_WORKERS=""
READY_OTHERS=""
for n in $ALL_NODES; do
  if is_control_plane "$n"; then
    if is_ready "$n"; then READY_OTHERS="$READY_OTHERS $n"; fi
  else
    if is_ready "$n"; then READY_WORKERS="$READY_WORKERS $n"; fi
  fi
done

W1=$(nth "$READY_WORKERS" 1)
W2=$(nth "$READY_WORKERS" 2)
O1=$(nth "$READY_OTHERS" 1)
N1=$(nth "$ALL_NODES" 1)
N2=$(nth "$ALL_NODES" 2)

if [ -n "$W2" ]; then
  CORDONED="$W1"; TAINTED="$W2"; MODE="two Ready worker nodes"
elif [ -n "$W1" ] && [ -n "$O1" ]; then
  CORDONED="$W1"; TAINTED="$O1"; MODE="one Ready worker node and one Ready control-plane node"
elif [ -n "$W1" ]; then
  CORDONED="$W1"; TAINTED="$W1"; MODE="one Ready worker node - both problems on the same node"
elif [ -n "$O1" ]; then
  CORDONED="$O1"; TAINTED="$O1"; MODE="one Ready control-plane node - both problems on the same node"
else
  CORDONED="$N1"; TAINTED="${N2:-$N1}"; MODE="no Ready node available"
fi

if [ "$CORDONED" = "$TAINTED" ]; then
  echo "   WARN: this cluster does not have two usable nodes, so the cordoned" >&2
  echo "         node and the tainted node are the same node ($CORDONED)." >&2
fi

# ---------------------------------------------------------------------------
# Break the two nodes, in the two different ways
# ---------------------------------------------------------------------------

kubectl cordon "$CORDONED"
kubectl taint node "$TAINTED" "$TAINT_KEY=$TAINT_VALUE:$TAINT_EFFECT" --overwrite >/dev/null

# ---------------------------------------------------------------------------
# Wait until the cluster actually shows the broken state
# ---------------------------------------------------------------------------

i=0
while [ "$i" -lt 30 ]; do
  UNSCHED=$(kubectl get node "$CORDONED" -o jsonpath='{.spec.unschedulable}' 2>/dev/null || true)
  TAINTOK=$(kubectl get node "$TAINTED" \
              -o jsonpath='{range .spec.taints[?(@.key=="dedicated")]}{.value}{end}' 2>/dev/null || true)
  if [ "$UNSCHED" = "true" ] && [ "$TAINTOK" = "$TAINT_VALUE" ]; then break; fi
  sleep 1
  i=$((i+1))
done

# ---------------------------------------------------------------------------
# Record which node is which
# ---------------------------------------------------------------------------

cat > "$STATE" <<EOF
CORDONED=$CORDONED
TAINTED=$TAINTED
EOF

echo "w11 environment ready"
echo "   - cordoned node (unschedulable): $CORDONED"
echo "   - tainted node ($TAINT_KEY=$TAINT_VALUE:$TAINT_EFFECT): $TAINTED"
echo "   - node layout: $MODE"
echo "   - state file: $STATE"
echo "   - Task: make the cordoned node schedulable again, remove the taint,"
echo "     label the node that carried the taint with $LABEL_KEY=$LABEL_VALUE,"
echo "     and show it with: kubectl get nodes -l $LABEL_KEY=$LABEL_VALUE"

if [ "$UNSCHED" != "true" ]; then
  echo "   WARN: $CORDONED does not report unschedulable yet. Check:" >&2
  echo "         kubectl get node $CORDONED" >&2
fi
if [ "$TAINTOK" != "$TAINT_VALUE" ]; then
  echo "   WARN: $TAINTED does not carry the $TAINT_KEY=$TAINT_VALUE taint yet. Check:" >&2
  echo "         kubectl get node $TAINTED" >&2
fi
