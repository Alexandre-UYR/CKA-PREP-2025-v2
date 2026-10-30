#!/bin/bash
set -e

# c6 — Taint and untaint
#
# Pre-state:
#   - namespace `taints`
#   - a Deployment `workload` (nginx, 1 replica, labels app=workload) whose
#     pod cannot be scheduled on the node the task is about
#   - one worker node tainted dedicated=payments:NoSchedule
#   - another node tainted do-not-use=true:NoSchedule
#
# The two taints are recorded in /tmp/cka-lab/c6.nodes, and the Deployment's
# UID in /tmp/cka-lab/c6.uid, so the grader can tell which node carried which
# taint and whether the Deployment was patched or re-created.

STATE=/tmp/cka-lab
NS=taints
NODES_FILE="$STATE/c6.nodes"
UID_FILE="$STATE/c6.uid"

mkdir -p "$STATE"

# ------------------------------------------------- 0. clean our own taints --

# The setup has to be safe to run twice, so the taints it applies are removed
# before it applies them again. `kubectl taint` has no --ignore-not-found:
# removing a taint that is not there is an error, which is harmless here.
for n in $(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
  kubectl taint nodes "$n" dedicated=payments:NoSchedule- >/dev/null 2>&1 || true
  kubectl taint nodes "$n" do-not-use=true:NoSchedule- >/dev/null 2>&1 || true
done

# ------------------------------------------------------------ 1. the nodes --

# The worker nodes. The label selector is used because `!key` means "the label
# is absent", which is still true when the label exists with an empty value -
# and that is how kubeadm labels a control-plane node
# (node-role.kubernetes.io/control-plane: ""). A jsonpath check on the label's
# value cannot tell that apart from "no label at all".
WORKERS=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane,!node-role.kubernetes.io/master' -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | sed '/^$/d')

if [ -z "$WORKERS" ]; then
  echo "ERROR: no worker node found. c6 needs at least one worker node." >&2
  exit 1
fi

WORKER_COUNT=$(printf '%s\n' "$WORKERS" | wc -l | tr -d ' ')
PAYMENTS=$(printf '%s\n' "$WORKERS" | sed -n 1p)

if [ "$WORKER_COUNT" -ge 2 ]; then
  DNU=$(printf '%s\n' "$WORKERS" | sed -n 2p)
else
  # Only one worker: the second taint goes on the control-plane node. It is
  # already tainted by kubeadm, so this changes nothing about what can run
  # there - it just gives the do-not-use taint a node of its own.
  DNU=$(kubectl get nodes -l 'node-role.kubernetes.io/control-plane' -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | sed '/^$/d' | sed -n 1p)
  if [ -z "$DNU" ]; then
    DNU=$(kubectl get nodes -l 'node-role.kubernetes.io/master' -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | sed '/^$/d' | sed -n 1p)
  fi
  if [ -z "$DNU" ]; then
    echo "ERROR: c6 needs at least two nodes - one to carry dedicated=payments" >&2
    echo "       and another to carry do-not-use." >&2
    exit 1
  fi
fi

if [ "$PAYMENTS" = "$DNU" ]; then
  echo "ERROR: c6 needs two different nodes (payments and do-not-use)." >&2
  exit 1
fi

{
  echo "payments $PAYMENTS"
  echo "do-not-use $DNU"
} > "$NODES_FILE"

# ------------------------------------------------------------- 2. the taints -

# Applied before the Deployment exists, so the pod cannot slip onto a node
# that has just been tainted.
kubectl taint nodes "$PAYMENTS" dedicated=payments:NoSchedule --overwrite
kubectl taint nodes "$DNU" do-not-use=true:NoSchedule --overwrite

# --------------------------------------------------- 3. namespace + workload --

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

# The Deployment is re-created from scratch every time, so the pre-state always
# has the same pod template - no toleration, no nodeSelector, no affinity.
kubectl -n "$NS" delete deployment workload --ignore-not-found --wait=true >/dev/null 2>&1 || true
kubectl -n "$NS" delete pods -l app=workload --ignore-not-found --wait=true >/dev/null 2>&1 || true

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload
  namespace: taints
  labels:
    app: workload
spec:
  replicas: 1
  selector:
    matchLabels:
      app: workload
  template:
    metadata:
      labels:
        app: workload
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports:
            - containerPort: 80
EOF

# ------------------------------------------------------------- 4. the UID ----

# The task says the Deployment must be patched, not re-created. The UID is how
# the grader proves that: a patched object keeps its UID, a re-created one
# gets a new one.
kubectl -n "$NS" get deployment workload -o jsonpath='{.metadata.uid}' > "$UID_FILE"

echo "c6 environment ready"
echo "   - namespace: $NS"
echo "   - deployment: workload (nginx, 1 replica, labels app=workload)"
echo "   - $PAYMENTS carries dedicated=payments:NoSchedule"
echo "   - $DNU carries do-not-use=true:NoSchedule"
echo "   - state files: $NODES_FILE $UID_FILE"
