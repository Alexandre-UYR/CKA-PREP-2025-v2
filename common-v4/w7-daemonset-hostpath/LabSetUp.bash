#!/bin/bash
set -e

# w7 - One pod on every node
#
# The pre-state is the cluster, not the namespace:
#
#   the control-plane node   tainted NoSchedule, so a pod that does not
#                             tolerate it is skipped there
#   every other node         untainted
#
# The DaemonSet controller places pods itself: it wants one pod on every node
# in the cluster, it ignores the `unschedulable` flag on a node, and it does
# respect taints. Without a toleration for the control-plane taint the pod on
# that node never runs, so DESIRED stops being the number of nodes.
#
# The namespace is recreated on every run so the starting state is the same
# every time. A taint the setup had to add belongs to the setup, so the reset
# takes it away again; a taint the cluster already had is left alone.

NS=agent
LABDIR=/tmp/cka-lab
CP_TAINT_KEY=node-role.kubernetes.io/control-plane
CP_TAINT_EFFECT=NoSchedule

mkdir -p "$LABDIR"

ensure_ns(){
  local ns=$1 phase i
  if kubectl get ns "$ns" >/dev/null 2>&1; then
    phase=$(kubectl get ns "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [ "$phase" = "Terminating" ]; then
      i=0
      while [ "$i" -lt 60 ]; do
        kubectl get ns "$ns" >/dev/null 2>&1 || break
        sleep 2
        i=$((i+2))
      done
    fi
  fi
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
}

node_taints(){
  kubectl get node "$1" -o jsonpath='{range .spec.taints[*]}{.key}{"="}{.effect}{"\n"}{end}' 2>/dev/null || true
}

ensure_ns "$NS"

# ---- the ConfigMap ---------------------------------------------------------

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluentd-config
  namespace: $NS
data:
  fluent-bit.conf: |
    [SERVICE]
        Flush           5
        Log_Level       info
        Daemon          Off
    [INPUT]
        Name            tail
        Tag             kube.*
        Path            /var/log/containers/*.log
        Mem_Buf_Limit   5MB
        Skip_Long_Lines On
    [OUTPUT]
        Name            stdout
        Match           *
  fluent.conf: |
    <source>
      @type tail
      path /var/log/containers/*.log
      tag kube.*
      <parse>
        @type cri
      </parse>
    </source>
    <match **>
      @type stdout
    </match>
EOF

# ---- the nodes -------------------------------------------------------------

NODES=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
if [ -z "$NODES" ]; then
  echo "w7 setup: the cluster reports no nodes - there is nothing to build the pre-state on." >&2
  exit 1
fi
NODE_COUNT=$(printf '%s\n' "$NODES" | grep -c . | tr -d ' ')

# ---- the control-plane node and its taint -----------------------------------

CP_NODE=""
for n in $NODES; do
  lbl=$(kubectl get node "$n" -o jsonpath='{.metadata.labels}' 2>/dev/null || true)
  case "$lbl" in
    *node-role.kubernetes.io/control-plane*|*node-role.kubernetes.io/master*)
      CP_NODE="$n"; break;;
  esac
done

EFFECTIVE_KEY=""
EFFECTIVE_EFFECT=""
TAINT_ADDED="no"

if [ -n "$CP_NODE" ]; then
  while IFS='=' read -r tk te; do
    [ -n "$tk" ] || continue
    if [ "$te" = "NoSchedule" ] || [ "$te" = "NoExecute" ]; then
      EFFECTIVE_KEY="$tk"; EFFECTIVE_EFFECT="$te"; break
    fi
  done <<EOF
$(node_taints "$CP_NODE")
EOF

  if [ -z "$EFFECTIVE_KEY" ]; then
    # The control-plane node is not tainted. The question turns on the taint,
    # so add it - and remember that the setup added it, so the reset takes it
    # away again.
    echo "The control-plane node $CP_NODE carries no NoSchedule taint - adding $CP_TAINT_KEY:$CP_TAINT_EFFECT."
    kubectl taint node "$CP_NODE" "$CP_TAINT_KEY:$CP_TAINT_EFFECT" --overwrite >/dev/null
    EFFECTIVE_KEY="$CP_TAINT_KEY"
    EFFECTIVE_EFFECT="$CP_TAINT_EFFECT"
    TAINT_ADDED="yes"
  fi
else
  echo "w7 setup: no node carries a control-plane role - there is no tainted node to tolerate." >&2
fi

# ---- record the state the validator needs -----------------------------------

printf '%s\n' "$CP_NODE" > "$LABDIR/w7.cpnode"
printf '%s\n' "$NODE_COUNT" > "$LABDIR/w7.nodes"
printf '%s\n' "$TAINT_ADDED" > "$LABDIR/w7.taint.added"
if [ -n "$EFFECTIVE_KEY" ]; then
  printf '%s:%s\n' "$EFFECTIVE_KEY" "$EFFECTIVE_EFFECT" > "$LABDIR/w7.taint"
else
  : > "$LABDIR/w7.taint"
fi

# ---- a previous attempt's DaemonSet is not part of the pre-state ------------

kubectl -n "$NS" delete daemonset fluentd --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1 || true

# ---- probe the pre-state ----------------------------------------------------
# A DaemonSet with no toleration must not be able to run on the tainted node.
# The probe lives in its own namespace and is removed again, so the candidate
# inherits the environment and nothing else.

PROBE_SKIPPED="no"
if [ -n "$CP_NODE" ]; then
  echo "Probing the environment: a DaemonSet without a toleration must skip the tainted node..."

  kubectl create namespace agent-probe --dry-run=client -o yaml | kubectl apply -f - >/dev/null

  cat <<'EOF' | kubectl apply -f - >/dev/null
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: probe
  namespace: agent-probe
spec:
  selector:
    matchLabels:
      app: probe
  template:
    metadata:
      labels:
        app: probe
    spec:
      containers:
        - name: probe
          image: busybox:1.36
          command: ["sh", "-c", "sleep 3600"]
EOF

  PROBE_DESIRED=""
  PROBE_READY=""
  i=0
  while [ "$i" -lt 45 ]; do
    PROBE_DESIRED=$(kubectl -n agent-probe get daemonset probe -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || true)
    PROBE_READY=$(kubectl -n agent-probe get daemonset probe -o jsonpath='{.status.numberReady}' 2>/dev/null || true)
    if [ -n "$PROBE_DESIRED" ] && [ "${PROBE_DESIRED:-0}" -gt 0 ] 2>/dev/null; then
      if [ "${PROBE_READY:-0}" -ge "$PROBE_DESIRED" ] 2>/dev/null; then break; fi
      if [ "$PROBE_DESIRED" -ge "$NODE_COUNT" ] 2>/dev/null && [ "${PROBE_READY:-0}" -lt "$NODE_COUNT" ] 2>/dev/null; then
        # Every node is wanted, but not every node has a running pod: the
        # tainted one is the one that is missing.
        break
      fi
    fi
    sleep 2
    i=$((i+2))
  done

  kubectl delete namespace agent-probe --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

  if [ -n "$PROBE_DESIRED" ] && [ "$PROBE_READY" -lt "$NODE_COUNT" ] 2>/dev/null; then
    PROBE_SKIPPED="yes"
  fi
fi

# ---- report -----------------------------------------------------------------

echo "✅ w7 environment ready"
echo "   - namespace: $NS"
echo "   - ConfigMap: fluentd-config (keys: fluent-bit.conf, fluent.conf)"
echo "   - nodes: $NODE_COUNT"
if [ -n "$CP_NODE" ]; then
  echo "   - control-plane node: $CP_NODE"
  echo "   - its taint: $EFFECTIVE_KEY:$EFFECTIVE_EFFECT (added by this setup: $TAINT_ADDED)"
else
  echo "   - control-plane node: none - the cluster has no node with a control-plane role"
fi
echo "   - Task: run one fluentd pod on every node, the tainted one included"

if [ "$PROBE_SKIPPED" = "yes" ]; then
  echo "   - probe confirmed: without a toleration only $PROBE_READY of $NODE_COUNT nodes had a running pod"
elif [ -n "$CP_NODE" ]; then
  echo "   ⚠️  The probe did not show the tainted node being skipped (desired '$PROBE_DESIRED', ready '$PROBE_READY')." >&2
  echo "      Check: kubectl get node $CP_NODE -o jsonpath='{.spec.taints}'" >&2
else
  echo "   - no probe: the cluster has no control-plane node"
fi
