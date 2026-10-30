#!/bin/bash
set -e

# v8 - One pod per node, including the control plane
#
# The pre-state is the cluster itself, not the namespace:
#
#   control-plane node   tainted node-role.kubernetes.io/control-plane:NoSchedule
#   one node             labelled monitoring=yes
#
# A DaemonSet lands on every node EXCEPT a tainted one, unless the pod template
# tolerates the taint - so the control-plane node is silently skipped until the
# candidate adds a toleration. The monitoring=yes label is the other half of
# the trap: it looks like a reason to write a nodeSelector, and a nodeSelector
# takes the DaemonSet off every other node.
#
# The namespace is recreated on every run so the setup is idempotent and the
# starting state is always the same. The taint belongs to the cluster, so the
# reset leaves it alone.

NS=ds
LABDIR="/tmp/cka-lab"
TAINT_KEY=node-role.kubernetes.io/control-plane
MASTER_KEY=node-role.kubernetes.io/master
TAINT_EFFECT=NoSchedule

mkdir -p "$LABDIR"

# ---- helpers ----------------------------------------------------------------

node_taint_keys(){
  kubectl get node "$1" -o jsonpath='{.spec.taints[*].key}' 2>/dev/null | tr ' ' '\n'
}

has_taint(){
  local node=$1 key=$2
  node_taint_keys "$node" | grep -qx "$key"
}

is_control_plane(){
  kubectl get node "$1" -o jsonpath='{.metadata.labels}' 2>/dev/null \
    | grep -Eq 'node-role\.kubernetes\.io/(control-plane|master)'
}

# ---- the namespace ----------------------------------------------------------

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

# ---- the control-plane node and its taint -----------------------------------

NODES=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)
if [ -z "$NODES" ]; then
  echo "v8 setup: the cluster reports no nodes - there is nothing to build the pre-state on." >&2
  exit 1
fi

CP_NODE=""
for n in $NODES; do
  if has_taint "$n" "$TAINT_KEY"; then CP_NODE="$n"; break; fi
done
if [ -z "$CP_NODE" ]; then
  # An older cluster taints the control plane with the master key instead.
  for n in $NODES; do
    if has_taint "$n" "$MASTER_KEY"; then CP_NODE="$n"; break; fi
  done
fi
if [ -z "$CP_NODE" ]; then
  # No taint anywhere: take the node that wears the control-plane role.
  for n in $NODES; do
    if is_control_plane "$n"; then CP_NODE="$n"; break; fi
  done
fi
if [ -z "$CP_NODE" ]; then
  CP_NODE=$(printf '%s\n' "$NODES" | head -n 1)
fi

EFFECTIVE_KEY="$TAINT_KEY"
if has_taint "$CP_NODE" "$TAINT_KEY"; then
  EFFECTIVE_KEY="$TAINT_KEY"
elif has_taint "$CP_NODE" "$MASTER_KEY"; then
  # Leave the cluster's own taint alone. Adding a second, different taint would
  # mean the candidate had to tolerate two keys to get onto the node.
  EFFECTIVE_KEY="$MASTER_KEY"
else
  echo "The control-plane node $CP_NODE carries no control-plane taint - adding $TAINT_KEY:$TAINT_EFFECT."
  kubectl taint nodes "$CP_NODE" "$TAINT_KEY:$TAINT_EFFECT" --overwrite
  EFFECTIVE_KEY="$TAINT_KEY"
fi

# ---- the monitoring label ---------------------------------------------------

MON_NODE=$(kubectl get nodes -l monitoring=yes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -z "$MON_NODE" ]; then
  # Prefer a node that is not the control plane, so the label is not a hint
  # about which node needs the toleration.
  MON_NODE=""
  for n in $NODES; do
    if [ "$n" != "$CP_NODE" ]; then MON_NODE="$n"; break; fi
  done
  [ -z "$MON_NODE" ] && MON_NODE="$CP_NODE"
  kubectl label node "$MON_NODE" monitoring=yes --overwrite
fi

NODE_COUNT=$(printf '%s\n' "$NODES" | grep -c . | tr -d ' ')

# ---- record the environment -------------------------------------------------

printf '%s:%s\n' "$EFFECTIVE_KEY" "$TAINT_EFFECT" > "$LABDIR/v8.taint"
printf '%s\n' "$CP_NODE" > "$LABDIR/v8.cpnode"
printf '%s\n' "$MON_NODE" > "$LABDIR/v8.monitor"
printf '%s\n' "$NODE_COUNT" > "$LABDIR/v8.nodes"

# ---- prove the pre-state is broken ------------------------------------------
# A DaemonSet with no toleration is scheduled on every node and never lands on
# the tainted one. The probe lives in its own namespace and is removed again,
# so the candidate inherits the environment and nothing else.

echo "Probing the environment: a DaemonSet without a toleration must skip the tainted node..."
kubectl create namespace ds-probe --dry-run=client -o yaml | kubectl apply -f -

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: probe
  namespace: ds-probe
spec:
  selector:
    matchLabels:
      app: probe
  template:
    metadata:
      labels:
        app: probe
    spec:
      hostNetwork: true
      containers:
        - name: probe
          image: busybox:1.36
          command: ["sh", "-c", "sleep 3600"]
EOF

PROBE_DESIRED=""
PROBE_READY=""
PROBE_CP_PHASE=""
PROBE_OTHER_READY=0
PROBE_SKIP=0
i=0
while [ "$i" -lt 60 ]; do
  PROBE_DESIRED=$(kubectl -n ds-probe get daemonset probe -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || true)
  PROBE_READY=$(kubectl -n ds-probe get daemonset probe -o jsonpath='{.status.numberReady}' 2>/dev/null || true)
  PODLIST=$(kubectl -n ds-probe get pods \
               -o jsonpath='{range .items[*]}{.spec.nodeName}{"|"}{.status.phase}{"\n"}{end}' 2>/dev/null || true)
  PROBE_CP_PHASE=$(printf '%s\n' "$PODLIST" | awk -F'|' -v n="$CP_NODE" '$1==n {print $2}' | head -n 1)
  PROBE_OTHER_READY=$(printf '%s\n' "$PODLIST" | awk -F'|' -v n="$CP_NODE" '$1!="" && $1!=n && $2=="Running" {c++} END {print c+0}')
  # The controller wants a pod on every node, the pod on the tainted node is
  # stuck Pending, and - unless the control plane is the only node there is -
  # the other nodes are running. The last part is what tells an untolerated
  # taint apart from a failed image pull.
  if [ -n "$PROBE_DESIRED" ] && [ -n "$PROBE_READY" ] && [ "$PROBE_CP_PHASE" = "Pending" ]; then
    if [ "$PROBE_READY" -lt "$PROBE_DESIRED" ] 2>/dev/null \
       && { [ "$PROBE_OTHER_READY" -ge 1 ] 2>/dev/null || [ "$NODE_COUNT" -le 1 ]; }; then
      PROBE_SKIP=1
      break
    fi
  fi
  sleep 2
  i=$((i+2))
done

kubectl delete namespace ds-probe --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# ---- report -----------------------------------------------------------------

echo "✅ v8 environment ready"
echo "   - namespace: $NS"
echo "   - nodes: $NODE_COUNT"
echo "   - control-plane node: $CP_NODE"
echo "   - its taint: $EFFECTIVE_KEY:$TAINT_EFFECT"
echo "   - node labelled monitoring=yes: $MON_NODE"
echo "   - recorded taint: $LABDIR/v8.taint"
echo "   - Task: put one agent pod on every node, the tainted one included"

if [ "$PROBE_SKIP" -eq 1 ]; then
  echo "   - probe confirmed: the pod on $CP_NODE stayed Pending (untolerated taint), $PROBE_READY of $PROBE_DESIRED nodes took a pod"
else
  echo "   ⚠️  The probe did not show the tainted node being skipped (desired '$PROBE_DESIRED', ready '$PROBE_READY', pod on $CP_NODE '$PROBE_CP_PHASE', other nodes running '$PROBE_OTHER_READY')." >&2
  echo "      Check the taint on $CP_NODE and the probe's events." >&2
fi
if [ "$PROBE_DESIRED" != "$NODE_COUNT" ] 2>/dev/null; then
  echo "   ⚠️  The DaemonSet controller only counts $PROBE_DESIRED of $NODE_COUNT nodes as eligible." >&2
  echo "      A DaemonSet with no node selector and no toleration should want a pod on every node." >&2
fi
