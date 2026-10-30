#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

STATE=/tmp/cka-lab
NODE_FILE="$STATE/c5.node"
DEBUG_NS=default
DEBUG_WAIT=45

# ---------------------------------------------------------------- helpers --

minikube_profiles(){
  minikube profile list 2>/dev/null \
    | awk -F'|' 'NF>2 {gsub(/^[ \t]+|[ \t]+$/, "", $2); if ($2 != "" && $2 != "Profile") print $2}'
}

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
  addr=$(k get node "$node" -o jsonpath='{range .status.addresses[?(@.type=="InternalIP")]}{.address}{"\n"}{end}' 2>/dev/null | head -1)
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

DEBUG_ERR=""
debug_node(){
  local __v=$1 node=$2
  shift 2
  local dout dpod dphase di podout drc=0
  DEBUG_ERR=""
  dout=$(k debug "node/$node" -n "$DEBUG_NS" --image=busybox -- "$@" 2>&1) || drc=$?
  if [ "$drc" -ne 0 ]; then
    DEBUG_ERR="kubectl debug failed: $(printf '%s' "$dout" | tr '\n' ' ')"
    return 1
  fi
  dpod=$(printf '%s\n' "$dout" | tr ' ' '\n' | grep -- '-debugger-' | head -1)
  if [ -z "$dpod" ]; then
    dpod=$(k get pods -n "$DEBUG_NS" --field-selector "spec.nodeName=$node" -o name 2>/dev/null | grep 'node-debugger' | head -1 | cut -d/ -f2)
  fi
  if [ -z "$dpod" ]; then
    DEBUG_ERR="no helper pod could be created on $node"
    return 1
  fi
  dphase=""
  di=0
  while [ "$di" -lt "$DEBUG_WAIT" ]; do
    dphase=$(k get pod "$dpod" -n "$DEBUG_NS" -o jsonpath='{.status.phase}' 2>/dev/null) || dphase=""
    case "$dphase" in Succeeded|Failed) break;; esac
    sleep 2
    di=$((di+2))
  done
  podout=$(k logs "$dpod" -n "$DEBUG_NS" 2>&1) || podout=""
  k delete pod "$dpod" -n "$DEBUG_NS" --ignore-not-found >/dev/null 2>&1 || true
  if [ "$dphase" != "Succeeded" ]; then
    DEBUG_ERR="the helper pod on $node never ran the command (phase: ${dphase:-unknown})"
    return 1
  fi
  eval "$__v=\$podout"
  return 0
}

# ------------------------------------------------------------------ reset --

NODE=""
if [ -f "$NODE_FILE" ]; then
  NODE=$(tr -d '[:space:]' < "$NODE_FILE" 2>/dev/null || true)
fi

if [ -n "$NODE" ] && k get node "$NODE" >/dev/null 2>&1; then
  if node_run "$NODE" "systemctl start kubelet && systemctl enable kubelet" >/dev/null 2>&1; then
    echo "c5 reset: kubelet on $NODE started and enabled"
  else
    out=""
    if debug_node out "$NODE" chroot /host sh -c 'systemctl start kubelet; systemctl enable kubelet'; then
      echo "c5 reset: kubelet on $NODE started and enabled (through a helper pod)"
    else
      echo "c5 reset: WARNING - could not reach $NODE to start the kubelet" >&2
      echo "            SSH in and run: systemctl enable --now kubelet" >&2
    fi
  fi
fi

# Any helper pod the exercise left behind (only the node-debugger ones).
for p in $(k get pods -n "$DEBUG_NS" -o name 2>/dev/null | grep 'node-debugger'); do
  k delete "$p" -n "$DEBUG_NS" --ignore-not-found >/dev/null 2>&1 || true
done

rm -f "$NODE_FILE" 2>/dev/null || true

echo "c5 reset: done"
