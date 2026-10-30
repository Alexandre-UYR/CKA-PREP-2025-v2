#!/bin/bash
set -e

# v5 - The pod that has been Pending for ten minutes
#
# The pre-state is a Pod that cannot be placed, plus two nodes that each
# refuse new pods for a different reason:
#
#   node A  labelled disk=hdd, CORDONED              -> "was cordoned"
#   node B  labelled disk=nvme, tainted NoSchedule   -> "had untolerated taint"
#   pod     nodeSelector disk=ssd                   -> "didn't match Pod's
#                                                       node affinity/selector"
#
# The scheduler lists all three reasons in the pod's Events. The candidate has
# to read them and work out which node to fix.
#
# The namespace and the Pod are recreated on every run, so the setup is
# idempotent and the starting state is always the same.

NS=sched
POD=stuck
IMAGE=nginx:1.25
STATE_FILE="${TMPDIR:-/tmp}/cka-v5-scheduling-diagnosis.env"

is_control_plane(){
  kubectl get node "$1" -o jsonpath='{.metadata.labels}' 2>/dev/null \
    | grep -Eq 'node-role\.kubernetes\.io/(control-plane|master)'
}

is_ready(){
  [ "$(kubectl get node "$1" -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status}{end}' 2>/dev/null)" = "True" ]
}

# ---- pick the two nodes the pre-state needs --------------------------------
# Two Ready worker nodes are the best case: one to cordon, one to taint. With a
# single worker the cordoned node falls back to a control-plane node and the
# worker keeps the taint, so the candidate's target is still the node with the
# single, fixable taint.

WORKERS=()
OTHERS=()
while IFS= read -r n; do
  [ -n "$n" ] || continue
  if is_control_plane "$n"; then OTHERS+=("$n"); else WORKERS+=("$n"); fi
done < <(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)

READY_WORKERS=()
for n in "${WORKERS[@]}"; do if is_ready "$n"; then READY_WORKERS+=("$n"); fi; done
READY_OTHERS=()
for n in "${OTHERS[@]}"; do if is_ready "$n"; then READY_OTHERS+=("$n"); fi; done

if [ "${#READY_WORKERS[@]}" -eq 0 ]; then READY_WORKERS=("${WORKERS[@]}"); fi
if [ "${#READY_OTHERS[@]}" -eq 0 ]; then READY_OTHERS=("${OTHERS[@]}"); fi

if [ "${#READY_WORKERS[@]}" -ge 2 ]; then
  NODE_A="${READY_WORKERS[0]}"
  NODE_B="${READY_WORKERS[1]}"
  MODE="two worker nodes"
elif [ "${#READY_WORKERS[@]}" -eq 1 ]; then
  NODE_A="${READY_OTHERS[0]:-${READY_WORKERS[0]}}"
  NODE_B="${READY_WORKERS[0]}"
  MODE="one worker node, cordoned node is a control-plane node"
else
  NODE_A="${READY_OTHERS[0]}"
  NODE_B="${READY_OTHERS[1]:-${READY_OTHERS[0]}}"
  MODE="no worker node available"
fi

if [ -z "$NODE_A" ]; then
  echo "This cluster reports no nodes at all. Nothing to set up." >&2
  exit 1
fi

# ---- put the two nodes into the broken state --------------------------------

if [ "$NODE_A" = "$NODE_B" ]; then
  # Only one node to play with: it is cordoned AND tainted, and the pod's
  # selector still does not match it. The candidate has to clear all three.
  kubectl label node "$NODE_A" disk=nvme --overwrite
  kubectl cordon "$NODE_A"
  kubectl taint node "$NODE_A" dedicated=db:NoSchedule --overwrite
else
  kubectl label node "$NODE_A" disk=hdd --overwrite
  kubectl cordon "$NODE_A"
  kubectl label node "$NODE_B" disk=nvme --overwrite
  kubectl taint node "$NODE_B" dedicated=db:NoSchedule --overwrite
fi

# ---- the namespace and the stuck pod ---------------------------------------

kubectl delete namespace "$NS" --ignore-not-found --timeout=120s
kubectl create namespace "$NS"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $POD
  namespace: $NS
  labels:
    app: $POD
spec:
  nodeSelector:
    disk: ssd
  containers:
    - name: web
      image: $IMAGE
      imagePullPolicy: IfNotPresent
EOF

# ---- wait for the scheduler to deliver its verdict -------------------------

echo "Waiting for the scheduler to reject the pod, so the pre-state is what the task describes..."
EVENTS=""
i=0
while [ "$i" -lt 60 ]; do
  EVENTS=$(kubectl -n "$NS" get events \
             -o jsonpath='{range .items[?(@.involvedObject.name=="stuck")]}{.reason}{" "}{end}' 2>/dev/null || true)
  case "$EVENTS" in *FailedScheduling*) break;; esac
  sleep 2
  i=$((i+2))
done

PHASE=$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null || true)
PLACED=$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)

# ---- record which node is which --------------------------------------------

cat > "$STATE_FILE" <<EOF
NODE_A=$NODE_A
NODE_B=$NODE_B
POD=$POD
NAMESPACE=$NS
EOF

echo "✅ v5 environment ready"
echo "   - namespace: $NS"
echo "   - Pod: $POD (image $IMAGE, nodeSelector disk=ssd), phase: ${PHASE:-<unknown>}"
echo "   - cordoned node (disk=hdd): $NODE_A"
echo "   - tainted node (disk=nvme, dedicated=db:NoSchedule): $NODE_B"
echo "   - node layout: $MODE"
echo "   - scheduler events: ${EVENTS:-<none yet>}"
echo "   - state file: $STATE_FILE"
echo "   - Task: read the scheduler's verdict, work out the reasons, and put the pod on a node that can run it"

if ! echo "$EVENTS" | grep -q FailedScheduling; then
  echo "   ⚠️  The scheduler has not reported FailedScheduling yet. Check:" >&2
  echo "      kubectl -n $NS describe pod $POD" >&2
fi
if [ -n "$PLACED" ]; then
  echo "   ⚠️  The pod was scheduled onto $PLACED - the pre-state is not broken." >&2
fi
