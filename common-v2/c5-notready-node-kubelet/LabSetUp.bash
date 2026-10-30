#!/bin/bash
set -e

# c5 — Bring a NotReady node back
#
# The pre-state is a cluster with a control-plane node and at least one worker
# node whose kubelet has been stopped. Nothing is wrong with the node's specs:
# the kubelet simply stopped reporting, so the control plane eventually marks
# the node NotReady. That is the situation the question describes, and it is
# what makes the question interesting — the fix is on the node, not in the
# API server.
#
# Run this on the machine that can reach the cluster AND the nodes.

STATE=/tmp/cka-lab
NODE_FILE="$STATE/c5.node"
DEBUG_NS=default
DEBUG_WAIT=45

mkdir -p "$STATE"

# ---------------------------------------------------------------- helpers --

# The names of the local minikube profiles.
minikube_profiles(){
  minikube profile list 2>/dev/null \
    | awk -F'|' 'NF>2 {gsub(/^[ \t]+|[ \t]+$/, "", $2); if ($2 != "" && $2 != "Profile") print $2}'
}

# Run a command on a node and print its output.
#   node_run <node> <command string>
# Tries, in order: minikube ssh, plain ssh to the node's InternalIP, and
# docker exec (kind names its node containers after the node). Returns 1 when
# none of them worked.
node_run(){
  local node=$1 cmd=$2 p host addr out
  if command -v minikube >/dev/null 2>&1; then
    for p in $(minikube_profiles); do
      host=$(minikube ssh -p "$p" -- hostname 2>/dev/null | tr -d '\r\n')
      if [ "$host" = "$node" ]; then
        if out=$(minikube ssh -p "$p" -- "$cmd" 2>&1); then
          printf '%s' "$out"; return 0
        fi
      fi
    done
  fi
  addr=$(kubectl get node "$node" -o jsonpath='{range .status.addresses[?(@.type=="InternalIP")]}{.address}{"\n"}{end}' 2>/dev/null | head -1)
  if [ -n "$addr" ]; then
    if out=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 "root@$addr" "$cmd" 2>&1); then
      printf '%s' "$out"; return 0
    fi
  fi
  if command -v docker >/dev/null 2>&1; then
    host=$(docker exec "$node" hostname 2>/dev/null | tr -d '\r\n')
    if [ "$host" = "$node" ]; then
      if out=$(docker exec "$node" sh -c "$cmd" 2>&1); then
        printf '%s' "$out"; return 0
      fi
    fi
  fi
  return 1
}

# Run a command on a node through a privileged helper pod.
#   debug_node <outvar> <node> <command> [args...]
# Leaves the pod output in <outvar>. Returns 1 when the helper pod could not
# be run; the reason is left in $DEBUG_ERR.
#
# The helper pod is pinned to the node with spec.nodeName, so it is created
# even when the node is NotReady — but it still needs a working kubelet on
# that node to actually start the container.
DEBUG_ERR=""
debug_node(){
  local __v=$1 node=$2
  shift 2
  local dout dpod dphase di podout drc=0
  DEBUG_ERR=""
  dout=$(kubectl debug "node/$node" -n "$DEBUG_NS" --image=busybox -- "$@" 2>&1) || drc=$?
  if [ "$drc" -ne 0 ]; then
    DEBUG_ERR="kubectl debug failed: $(printf '%s' "$dout" | tr '\n' ' ')"
    return 1
  fi
  dpod=$(printf '%s\n' "$dout" | tr ' ' '\n' | grep -- '-debugger-' | head -1)
  if [ -z "$dpod" ]; then
    dpod=$(kubectl get pods -n "$DEBUG_NS" --field-selector "spec.nodeName=$node" -o name 2>/dev/null | grep 'node-debugger' | head -1 | cut -d/ -f2)
  fi
  if [ -z "$dpod" ]; then
    DEBUG_ERR="no helper pod could be created on $node"
    return 1
  fi
  dphase=""
  di=0
  while [ "$di" -lt "$DEBUG_WAIT" ]; do
    dphase=$(kubectl get pod "$dpod" -n "$DEBUG_NS" -o jsonpath='{.status.phase}' 2>/dev/null) || dphase=""
    case "$dphase" in Succeeded|Failed) break;; esac
    sleep 2
    di=$((di+2))
  done
  podout=$(kubectl logs "$dpod" -n "$DEBUG_NS" 2>&1) || podout=""
  kubectl delete pod "$dpod" -n "$DEBUG_NS" --ignore-not-found >/dev/null 2>&1 || true
  if [ "$dphase" != "Succeeded" ]; then
    DEBUG_ERR="the helper pod on $node never ran the command (phase: ${dphase:-unknown})"
    return 1
  fi
  eval "$__v=\$podout"
  return 0
}

# Bring the kubelet on a node back up.
restore_kubelet(){
  local node=$1 out
  if node_run "$node" "systemctl start kubelet && systemctl enable kubelet" >/dev/null 2>&1; then
    return 0
  fi
  if debug_node out "$node" chroot /host sh -c 'systemctl start kubelet; systemctl enable kubelet'; then
    return 0
  fi
  return 1
}

# Stop the kubelet on a node.
stop_kubelet(){
  local node=$1 out
  if node_run "$node" "systemctl stop kubelet" >/dev/null 2>&1; then
    return 0
  fi
  # No shell access: run the command from a privileged helper pod instead.
  if debug_node out "$node" chroot /host systemctl stop kubelet; then
    return 0
  fi
  return 1
}

# ------------------------------------------------- 0. restore, then break --

# The setup must be safe to run twice, so any kubelet this exercise stopped
# earlier is started again before anything else happens.
if [ -f "$NODE_FILE" ]; then
  PREV=$(tr -d '[:space:]' < "$NODE_FILE" 2>/dev/null || true)
  if [ -n "$PREV" ] && kubectl get node "$PREV" >/dev/null 2>&1; then
    echo "c5: a previous run stopped the kubelet on $PREV - starting it again first"
    if ! restore_kubelet "$PREV"; then
      echo "ERROR: could not restore the kubelet on $PREV." >&2
      echo "       There is no SSH (or docker exec) to that node from this machine," >&2
      echo "       and a helper pod cannot start on a node whose kubelet is dead." >&2
      echo "       Start it by hand, then run this setup again." >&2
      exit 1
    fi
  fi
fi

# ------------------------------------------------------- 1. pick the node --

# The node must NOT be the control plane. The label selector is used first
# because `!key` means "the label is absent" — which is still true when the
# label exists with an empty value, and that is exactly how kubeadm labels a
# control-plane node (node-role.kubernetes.io/control-plane: ""). A jsonpath
# check on the label's value cannot tell that apart from "no label at all".
WORKERS=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane,!node-role.kubernetes.io/master' -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | sed '/^$/d')
if [ -z "$WORKERS" ]; then
  # Fallback for clusters that label the control plane some other way.
  WORKERS=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.labels.node-role\.kubernetes\.io/control-plane}{"\n"}{end}' | awk '$2==""{print $1; exit}')
fi
NODE=$(printf '%s\n' "$WORKERS" | head -1)

if [ -z "$NODE" ]; then
  echo "ERROR: no worker node found. c5 needs a cluster with a control-plane" >&2
  echo "       node and at least one worker node." >&2
  exit 1
fi

# --------------------------------------------------------- 2. break it -----

echo "c5: stopping the kubelet on $NODE"
if ! stop_kubelet "$NODE"; then
  echo "ERROR: could not stop the kubelet on $NODE." >&2
  echo "       This machine has no SSH to the node and no way to run a helper" >&2
  echo "       pod there. Check that you can reach the node." >&2
  exit 1
fi

echo "$NODE" > "$NODE_FILE"

# -------------------------------------------------------- 3. wait for it ---

# The node stays Ready for a short while after the kubelet stops: the control
# plane waits out the node-monitor grace period before it declares the node
# NotReady. Wait for that, so the pre-state is what the question says it is.
i=0
STATE=""
while [ "$i" -lt 120 ]; do
  STATE=$(kubectl get node "$NODE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null) || STATE=""
  case "$STATE" in
    False|Unknown) break;;
  esac
  sleep 5
  i=$((i+5))
done

if [ "$STATE" != "False" ] && [ "$STATE" != "Unknown" ]; then
  echo "WARNING: $NODE still reports Ready=$STATE - the kubelet may still be up." >&2
fi

echo "c5 environment ready"
echo "   - node with its kubelet stopped: $NODE (Ready=$STATE)"
echo "   - state file: $NODE_FILE"
echo "   - Task: bring the kubelet back (running AND enabled) and confirm the node is Ready"
