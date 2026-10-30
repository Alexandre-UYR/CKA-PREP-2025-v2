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

NS=scheduling
KEY=workload
VALUE=general

echo "== c8: Place a Pod on a specific node =="

# The node is looked up by its label, never by a name written into this
# script. The file the setup wrote is only a fallback for the case where the
# candidate removed the label again.
NODE=$(k get nodes -l "$KEY=$VALUE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$NODE" ]; then
  NODE=$(cat /tmp/cka-lab/c8.node 2>/dev/null)
  note "no node carries the label $KEY=$VALUE any more, falling back to the node recorded at setup time"
fi
nonempty "a node labelled $KEY=$VALUE exists" "$NODE"

if [ -z "$NODE" ]; then
  echo; echo -e "${R}c8 FAILED ($FAILS checks)${X}"; exit 1
fi

LABELLED=$(k get nodes -l "$KEY=$VALUE" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -c . || true)
if [ "${LABELLED:-0}" -gt 1 ]; then
  note "more than one node carries the label $KEY=$VALUE; the check uses the first one"
fi

# ---- the two Pods ----
if ! exists "Pod pinned exists in namespace $NS" -n "$NS" pod pinned; then
  echo; echo -e "${R}c8 FAILED ($FAILS checks)${X}"; exit 1
fi
if ! exists "Pod selected exists in namespace $NS" -n "$NS" pod selected; then
  echo; echo -e "${R}c8 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- pinned: pinned with nodeName ----
PIN_NODE=$(k -n "$NS" get pod pinned -o jsonpath='{.spec.nodeName}' 2>/dev/null)
eq "the pinned Pod has spec.nodeName set to the labelled node" "$PIN_NODE" "$NODE"

# ---- selected: pinned with a nodeSelector ----
SEL_KEY=$(k -n "$NS" get pod selected -o jsonpath='{.spec.nodeSelector.workload}' 2>/dev/null)
eq "the selected Pod has a nodeSelector with workload=general" "$SEL_KEY" "$VALUE"

SEL_NODE=$(k -n "$NS" get pod selected -o jsonpath='{.spec.nodeName}' 2>/dev/null)
eq "the selected Pod landed on the labelled node" "$SEL_NODE" "$NODE"

# ---- both must be up ----
for p in pinned selected; do
  PHASE=$(k -n "$NS" get pod "$p" -o jsonpath='{.status.phase}' 2>/dev/null)
  eq "the $p Pod is Running" "$PHASE" "Running"
done

note "nodeName bypasses the scheduler: the kubelet runs the Pod even if the"
note "node has no room for it, and NoSchedule taints are not enforced."
note "nodeSelector goes through the scheduler, so taints and resource limits"
note "are respected - and if nothing matches, the Pod stays Pending."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c8 PASSED${X}"; else echo -e "${R}c8 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
