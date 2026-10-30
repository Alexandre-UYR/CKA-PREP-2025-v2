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
skip(){ echo -e "\033[33mSKIP${X}  $1"; }

STATE=/tmp/cka-lab
NODE_FILE="$STATE/c5.node"
DEBUG_NS=default
DEBUG_WAIT=45

echo "== c5: Bring a NotReady node back =="

# ---------------------------------------------------------------- helpers --

minikube_profiles(){
  minikube profile list 2>/dev/null \
    | awk -F'|' 'NF>2 {gsub(/^[ \t]+|[ \t]+$/, "", $2); if ($2 != "" && $2 != "Profile") print $2}'
}

# Run a command on a node and print its output.
#   node_run <node> <command string>
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

# Run a command on a node through a privileged helper pod.
#   debug_node <outvar> <node> <command> [args...]
# Leaves the pod output in <outvar>. Returns 1 when the helper pod could not
# be run; the reason is left in $DEBUG_ERR.
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

# The state of the kubelet service on a node.
#   SVC_ACTIVE / SVC_ENABLED are set on success; SVC_ERR explains a failure.
SVC_ACTIVE=""
SVC_ENABLED=""
SVC_ERR=""
service_states(){
  local node=$1 logs
  SVC_ACTIVE=""
  SVC_ENABLED=""
  SVC_ERR=""
  if debug_node logs "$node" chroot /host sh -c 'systemctl is-active kubelet; systemctl is-enabled kubelet'; then
    SVC_ACTIVE=$(printf '%s\n' "$logs" | grep -E '^(active|inactive|failed|activating|deactivating|unknown)$' | head -1)
    SVC_ENABLED=$(printf '%s\n' "$logs" | grep -E '^(enabled|disabled|enabled-runtime|linked|static|masked|generated|transient|alias)$' | head -1)
    return 0
  fi
  SVC_ERR="$DEBUG_ERR"
  logs=$(node_run "$node" 'systemctl is-active kubelet; systemctl is-enabled kubelet' 2>/dev/null) || logs=""
  if [ -n "$logs" ]; then
    SVC_ACTIVE=$(printf '%s\n' "$logs" | grep -E '^(active|inactive|failed|activating|deactivating|unknown)$' | head -1)
    SVC_ENABLED=$(printf '%s\n' "$logs" | grep -E '^(enabled|disabled|enabled-runtime|linked|static|masked|generated|transient|alias)$' | head -1)
    return 0
  fi
  SVC_ERR="$SVC_ERR; no SSH to $node either"
  return 1
}

# ------------------------------------------------------------ find node ----

NODE=""
if [ -f "$NODE_FILE" ]; then
  NODE=$(tr -d '[:space:]' < "$NODE_FILE" 2>/dev/null || true)
fi
if [ -z "$NODE" ]; then
  note "no state file at $NODE_FILE - falling back to the node that is NotReady"
  for n in $(k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
    s=$(k get node "$n" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [ "$s" = "False" ] || [ "$s" = "Unknown" ]; then
      NODE="$n"
      break
    fi
  done
fi
if [ -z "$NODE" ]; then
  # Last resort: the exercise only ever breaks one worker node.
  W=$(k get nodes -l '!node-role.kubernetes.io/control-plane,!node-role.kubernetes.io/master' -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | sed '/^$/d' | head -1)
  NODE="$W"
fi

if [ -z "$NODE" ]; then
  bad "the node to repair could be identified (no state file, no NotReady node, no worker node)"
  echo
  echo -e "${R}c5 FAILED ($FAILS checks)${X}"
  exit 1
fi

if ! k get node "$NODE" >/dev/null 2>&1; then
  bad "node $NODE exists in the cluster"
  echo
  echo -e "${R}c5 FAILED ($FAILS checks)${X}"
  exit 1
fi

note "working on node: $NODE"

# ---------------------------------------------------------- 1. it is Ready --

# The node needs a moment to report again after the kubelet comes back.
READY=""
i=0
while [ "$i" -lt 45 ]; do
  READY=$(k get node "$NODE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null) || READY=""
  [ "$READY" = "True" ] && break
  sleep 3
  i=$((i+3))
done
eq "node $NODE reports Ready=True" "$READY" "True"

# ------------------------------------------------- 2. a kubelet is talking --

KV=$(k get node "$NODE" -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null)
nonempty "node $NODE reports a kubelet version (a kubelet is reporting in)" "$KV"

# ------------------------------------- 3. the kubelet is running and enabled --

if service_states "$NODE"; then
  eq "the kubelet service is running on $NODE (systemctl is-active)" "$SVC_ACTIVE" "active"
  eq "the kubelet service is enabled on $NODE (systemctl is-enabled)" "$SVC_ENABLED" "enabled"
else
  skip "the kubelet service is running on $NODE (systemctl is-active) - ${SVC_ERR}"
  skip "the kubelet service is enabled on $NODE (systemctl is-enabled) - ${SVC_ERR}"
fi

note "A NotReady node is almost always a kubelet or container-runtime problem."
note "kubectl describe node shows the heartbeat stopping, and the Ready"
note "condition turning Unknown once the node-monitor grace period runs out."
note "systemctl enable is what stops it happening again after a reboot."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c5 PASSED${X}"; else echo -e "${R}c5 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
