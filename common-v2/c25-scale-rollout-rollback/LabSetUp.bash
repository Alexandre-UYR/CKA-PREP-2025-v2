#!/bin/bash
set -e

# Pre-state for c25: the namespace the task names, and a healthy Deployment
# `api` that already has a rollout history.
#
# The history is created on purpose. A Deployment that has only ever been
# applied once has exactly one revision, and `kubectl rollout undo` restores
# the *previous* revision - so with a single revision there is nothing to roll
# back to, and the rollback in this question would be meaningless. The
# annotation below gives the Deployment a second revision with the same
# image, so the history the grader counts already has entries before the task
# starts.
#
# The Deployment's UID is recorded in /tmp/cka-lab/c25.uid. The task says the
# Deployment must not be deleted and re-created, and the UID is the only way
# to tell an edit from a re-creation.
NS=release
DEP=api
IMAGE=nginx:1.25
UIDFILE=/tmp/cka-lab/c25.uid

mkdir -p /tmp/cka-lab

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: release
  labels:
    app: api
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
        - name: api
          image: nginx:1.25
          ports:
            - containerPort: 80
EOF

# The second revision. A change to the pod template - here only an
# annotation - rolls out a new ReplicaSet and takes the Deployment to
# revision 2.
kubectl -n "$NS" patch deploy "$DEP" --type=strategic -p \
  '{"spec":{"template":{"metadata":{"annotations":{"cka-lab/c25-revision":"1"}}}}}'

# The Deployment has to be healthy and available before the task starts, or
# "the rollout has finished" would mean nothing.
kubectl -n "$NS" rollout status deploy/"$DEP" --timeout=180s

# Record the UID of the Deployment as it is now.
kubectl -n "$NS" get deploy "$DEP" -o jsonpath='{.metadata.uid}' > "$UIDFILE"

echo "✅ c25 environment ready"
echo "   - namespace: $NS"
echo "   - Deployment $DEP: 2 replicas of $IMAGE, labels app=api"
echo "   - rollout history: 2 revisions (the current one and an earlier one)"
echo "   - the Deployment's UID is recorded in $UIDFILE"
echo "   - Task: scale to 5, update the image to nginx:1.26, roll back, scale back to 2"
