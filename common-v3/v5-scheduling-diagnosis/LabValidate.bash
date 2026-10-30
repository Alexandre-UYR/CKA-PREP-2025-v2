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

NS=sched

echo "== v5: The pod that has been Pending for ten minutes =="

# ---- find the pod the candidate left behind --------------------------------
# The original Pod may have been deleted and re-created, and the replacement
# may have been given another name. Grade the pod that is actually running.

POD=""
if k -n "$NS" get pod stuck >/dev/null 2>&1; then
  if [ "$(k -n "$NS" get pod stuck -o jsonpath='{.status.phase}' 2>/dev/null)" = "Running" ]; then
    POD=stuck
  fi
fi
if [ -z "$POD" ]; then
  POD=$(k -n "$NS" get pods \
          -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
          | head -1)
fi
if [ -z "$POD" ]; then
  if k -n "$NS" get pod stuck >/dev/null 2>&1; then
    POD=stuck
  else
    POD=$(k -n "$NS" get pods -l app=stuck -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -z "$POD" ]; then
      POD=$(k -n "$NS" get pods -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    fi
  fi
fi

if [ -z "$POD" ]; then
  bad "a pod exists in namespace $NS"
  echo; echo -e "${R}v5 FAILED ($FAILS checks)${X}"; exit 1
fi
ok "a pod exists in namespace $NS (it is '$POD')"

# ---- it must be Running ----------------------------------------------------

PHASE=""
i=0
while [ "$i" -lt 20 ]; do
  PHASE=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null)
  [ "$PHASE" = "Running" ] && break
  sleep 2
  i=$((i+2))
done
eq "the pod '$POD' is Running" "$PHASE" "Running"

READY=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
eq "the container in '$POD' is ready" "$READY" "true"

# ---- it must be on a node, and that node must be able to run pods ----------

NODE=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.nodeName}' 2>/dev/null)
nonempty "the pod is scheduled onto a node" "$NODE"

if [ -z "$NODE" ]; then
  echo; echo -e "${R}v5 FAILED ($FAILS checks)${X}"; exit 1
fi

NODE_READY=$(k get node "$NODE" -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status}{end}' 2>/dev/null)
eq "node $NODE is Ready" "$NODE_READY" "True"

UNSCHED=$(k get node "$NODE" -o jsonpath='{.spec.unschedulable}' 2>/dev/null)
if [ "$UNSCHED" = "true" ]; then
  bad "node $NODE is not cordoned (it is unschedulable)"
else
  ok "node $NODE is not cordoned"
fi

TAINT=$(k get node "$NODE" -o jsonpath='{range .spec.taints[?(@.effect=="NoSchedule")]}X{end}' 2>/dev/null)
if [ -n "$TAINT" ]; then
  bad "node $NODE carries no NoSchedule taint (it has one)"
else
  ok "node $NODE carries no NoSchedule taint"
fi

# ---- say where it landed and what that node looks like ---------------------

TAINT_DETAIL=$(k get node "$NODE" -o jsonpath='{range .spec.taints[*]}{.key}={.value}:{.effect}{" "}{end}' 2>/dev/null)
echo
echo "   the pod '$POD' landed on node $NODE"
echo "   node $NODE: Ready=${NODE_READY:-unknown}  unschedulable=${UNSCHED:-false}  taints=${TAINT_DETAIL:-none}"

note "The scheduler's verdict is in the Events section of 'kubectl describe pod stuck':"
note "'didn't match Pod's node affinity/selector', 'had untolerated taint', 'was cordoned'."
note "Three reasons, three different fixes - and here all three were in play."
note "A Pod's nodeSelector cannot be edited after creation, so the fix is either"
note "to give a node the label the selector wants, or to re-create the Pod."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}v5 PASSED${X}"; else echo -e "${R}v5 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
