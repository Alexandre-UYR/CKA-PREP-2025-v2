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

NS=place
WORKLOAD_KEY=workload
WORKLOAD_VALUE=general

echo "== w12: Three ways of asking to be put somewhere =="

# ---------------------------------------------------------------------------
# The node is identified by its label, live. Nothing here is hard-coded.
# ---------------------------------------------------------------------------

NODE=$(k get nodes -l "$WORKLOAD_KEY=$WORKLOAD_VALUE" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$NODE" ]; then
  bad "a node labelled $WORKLOAD_KEY=$WORKLOAD_VALUE exists"
  echo; echo -e "${R}w12 FAILED ($FAILS checks)${X}"; exit 1
fi
ok "the node labelled $WORKLOAD_KEY=$WORKLOAD_VALUE is $NODE"

NODECOUNT=$(k get nodes -l "$WORKLOAD_KEY=$WORKLOAD_VALUE" -o name 2>/dev/null | grep -c 'node/' || true)
eq "exactly one node carries the label $WORKLOAD_KEY=$WORKLOAD_VALUE" "${NODECOUNT:-0}" "1"

exists "namespace $NS exists" ns "$NS"

# ---------------------------------------------------------------------------
# A helper for the three pods
# ---------------------------------------------------------------------------

pod_running(){
  # $1 = pod name
  k -n "$NS" get pod "$1" -o jsonpath='{.status.phase}' 2>/dev/null
}

pod_node(){
  # $1 = pod name
  k -n "$NS" get pod "$1" -o jsonpath='{.spec.nodeName}' 2>/dev/null
}

# ---------------------------------------------------------------------------
# pinned - nodeName
# ---------------------------------------------------------------------------

if ! exists "pod pinned exists in namespace $NS" -n "$NS" pod pinned; then
  skip "the pinned checks (there is no pod pinned)"
else
  PHASE=$(pod_running pinned)
  eq "pod pinned is Running" "$PHASE" "Running"
  NN=$(pod_node pinned)
  eq "pod pinned's nodeName is $NODE" "$NN" "$NODE"
fi

# ---------------------------------------------------------------------------
# selected - nodeSelector
# ---------------------------------------------------------------------------

if ! exists "pod selected exists in namespace $NS" -n "$NS" pod selected; then
  skip "the selected checks (there is no pod selected)"
else
  PHASE=$(pod_running selected)
  eq "pod selected is Running" "$PHASE" "Running"

  SELKEY=$(k -n "$NS" get pod selected -o jsonpath='{.spec.nodeSelector.workload}' 2>/dev/null)
  eq "pod selected's nodeSelector has $WORKLOAD_KEY=$WORKLOAD_VALUE" "$SELKEY" "$WORKLOAD_VALUE"

  LBL=$(k -n "$NS" get pod selected -o jsonpath='{.metadata.labels.app}' 2>/dev/null)
  eq "pod selected carries the label app=selected" "$LBL" "selected"

  NN=$(pod_node selected)
  eq "pod selected's nodeName is $NODE" "$NN" "$NODE"
fi

# ---------------------------------------------------------------------------
# together - pod affinity
# ---------------------------------------------------------------------------

AFF='.spec.affinity.podAffinity.requiredDuringSchedulingIgnoredDuringExecution'

if ! exists "pod together exists in namespace $NS" -n "$NS" pod together; then
  skip "the together checks (there is no pod together)"
else
  PHASE=$(pod_running together)
  eq "pod together is Running" "$PHASE" "Running"

  AFFOUT=$(k -n "$NS" get pod together -o jsonpath="{${AFF}}" 2>/dev/null)
  if [ -z "$AFFOUT" ]; then
    bad "pod together has a required pod affinity (none found)"
    skip "the labelSelector check"
    skip "the topologyKey check"
  else
    ok "pod together has a required pod affinity"

    # The selector has to match app=selected, in either of the two legal
    # ways of writing one.
    ML=$(k -n "$NS" get pod together \
          -o jsonpath="{${AFF}.labelSelector.matchLabels.app}" 2>/dev/null)
    ME=$(k -n "$NS" get pod together \
          -o jsonpath="{range ${AFF}.labelSelector.matchExpressions[?(@.key==\"app\")]}{.operator}{\"=\"}{range .values[*]}{.}{\",\"}{end}{end}}" 2>/dev/null)

    if [ "$ML" = "selected" ]; then
      ok "the affinity's labelSelector matches app=selected (matchLabels)"
    elif printf '%s' "$ME" | grep -q 'In' && printf '%s' "$ME" | grep -q 'selected'; then
      ok "the affinity's labelSelector matches app=selected (matchExpressions)"
    else
      bad "the affinity's labelSelector matches app=selected (got matchLabels.app='$ML', matchExpressions='$ME')"
    fi

    TOPO=$(k -n "$NS" get pod together -o jsonpath="{${AFF}.topologyKey}" 2>/dev/null)
    eq "the affinity's topologyKey is kubernetes.io/hostname" "$TOPO" "kubernetes.io/hostname"
  fi

  NN=$(pod_node together)
  eq "pod together's nodeName is $NODE" "$NN" "$NODE"
fi

note "nodeName bypasses the scheduler entirely: the kubelet runs the pod even"
note "if the node is out of room, and even if the node has taints."
note "nodeSelector and affinity go through the scheduler, so they respect"
note "taints and resource limits but need a node that actually matches."
note "Pod affinity is a statement about OTHER pods, not about the node."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}w12 PASSED${X}"; else echo -e "${R}w12 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
