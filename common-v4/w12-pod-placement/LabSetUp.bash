#!/bin/bash
set -e

# w12 - Three ways of asking to be put somewhere
#
# The pre-state is an empty namespace and a cluster with one worker node
# labelled workload=general. The candidate has to place three Pods on that
# node, each in a different way.
#
# The node is identified by its LABEL, never by its name: the name differs
# from one cluster to the next, and the whole point of the question is that
# the label is the portable handle.

NS=place
LABDIR=/tmp/cka-lab
STATE="$LABDIR/w12.node"
WORKLOAD_KEY=workload
WORKLOAD_VALUE=general

mkdir -p "$LABDIR"

is_control_plane(){
  kubectl get node "$1" -o jsonpath='{.metadata.labels}' 2>/dev/null \
    | grep -Eq 'node-role\.kubernetes\.io/(control-plane|master)'
}

is_ready(){
  [ "$(kubectl get node "$1" -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status}{end}' 2>/dev/null)" = "True" ]
}

has_noschedule_taint(){
  kubectl get node "$1" \
    -o jsonpath='{range .spec.taints[?(@.effect=="NoSchedule")]}x{end}' 2>/dev/null | grep -q 'x'
}

ALL_NODES=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)
if [ -z "$ALL_NODES" ]; then
  echo "This cluster reports no nodes at all. Nothing to set up." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# The control-plane node must carry the standard role label
# ---------------------------------------------------------------------------

CP=$(kubectl get nodes -l node-role.kubernetes.io/control-plane \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$CP" ]; then
  CP=$(kubectl get nodes -l node-role.kubernetes.io/master \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
fi
if [ -z "$CP" ]; then
  # A node whose name says what it is, but which has no role label yet.
  for n in $ALL_NODES; do
    case "$n" in
      *control-plane*|*master*) CP="$n"; break;;
    esac
  done
  if [ -n "$CP" ]; then
    kubectl label node "$CP" node-role.kubernetes.io/control-plane= --overwrite >/dev/null 2>&1 || true
  fi
fi
if [ -z "$CP" ]; then
  echo "   WARN: no control-plane node found in this cluster." >&2
fi

# ---------------------------------------------------------------------------
# Pick the node that will carry the workload=general label
# ---------------------------------------------------------------------------

TARGET=$(kubectl get nodes -l "$WORKLOAD_KEY=$WORKLOAD_VALUE" \
          -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$TARGET" ]; then
  # Prefer a Ready node that is not the control-plane.
  for n in $ALL_NODES; do
    if is_control_plane "$n"; then continue; fi
    if is_ready "$n"; then TARGET="$n"; break; fi
  done
fi
if [ -z "$TARGET" ]; then
  # Fall back to any Ready node at all.
  for n in $ALL_NODES; do
    if is_ready "$n"; then TARGET="$n"; break; fi
  done
fi
if [ -z "$TARGET" ]; then
  TARGET=$(echo "$ALL_NODES" | head -1)
fi

if [ -z "$TARGET" ]; then
  echo "This cluster reports no nodes at all. Nothing to set up." >&2
  exit 1
fi

# Exactly one node carries the label, or "the node labelled workload=general"
# would not identify anything.
for n in $ALL_NODES; do
  if [ "$n" != "$TARGET" ]; then
    kubectl label node "$n" "$WORKLOAD_KEY-" >/dev/null 2>&1 || true
  fi
done
kubectl label node "$TARGET" "$WORKLOAD_KEY=$WORKLOAD_VALUE" --overwrite >/dev/null

if has_noschedule_taint "$TARGET"; then
  echo "   WARN: $TARGET carries a NoSchedule taint, so a Pod that goes through" >&2
  echo "         the scheduler (nodeSelector, affinity) will not be placed there." >&2
  echo "         Check: kubectl describe node $TARGET" >&2
fi
if ! is_ready "$TARGET"; then
  echo "   WARN: $TARGET is not Ready, so the Pods may never start on it." >&2
fi

# ---------------------------------------------------------------------------
# The namespace, empty
# ---------------------------------------------------------------------------

kubectl delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

# ---------------------------------------------------------------------------
# Record the node's name for convenience
# ---------------------------------------------------------------------------

echo "$TARGET" > "$STATE"

echo "w12 environment ready"
echo "   - namespace: $NS (empty)"
echo "   - target node, labelled $WORKLOAD_KEY=$WORKLOAD_VALUE: $TARGET"
echo "   - control-plane node: ${CP:-<none found>}"
echo "   - state file: $STATE"
echo "   - Task: place 'pinned' (nodeName), 'selected' (nodeSelector, labelled"
echo "     app=selected) and 'together' (pod affinity on app=selected) on the"
echo "     node labelled $WORKLOAD_KEY=$WORKLOAD_VALUE, all Running"
