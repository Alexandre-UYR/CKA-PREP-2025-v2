#!/bin/bash
set -e

# x17 - The rollout that can never move
#
# The pre-state is a Deployment with three healthy pods running nginx:1.25,
# whose pod template has been changed to nginx:1.26 - and which will not roll
# that change out. The Deployment is paused, so the controller never starts
# the new ReplicaSet, and the old pods stay exactly where they are.
#
# (The other candidate explanation - a rolling update strategy with maxSurge
# and maxUnavailable both at zero - cannot be built through the API: the API
# server refuses it with "may not be 0 when `maxSurge` is 0". The exercise
# still teaches the rule, because the wrong answer is worth ruling out.)
#
# The fix is to the Deployment, in place, so the grader compares the UID.

NS=rollout
DEP=web
OLD_IMAGE=nginx:1.25
NEW_IMAGE=nginx:1.26
LABDIR=/tmp/cka-lab

mkdir -p "$LABDIR"

kubectl delete namespace "$NS" --ignore-not-found --wait=true --timeout=120s >/dev/null 2>&1 || true
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEP
  namespace: $NS
  labels:
    app: $DEP
spec:
  replicas: 3
  selector:
    matchLabels:
      app: $DEP
  template:
    metadata:
      labels:
        app: $DEP
    spec:
      containers:
        - name: $DEP
          image: $OLD_IMAGE
          ports:
            - containerPort: 80
EOF

echo "Waiting for the Deployment to become available..."
kubectl -n "$NS" rollout status deployment/"$DEP" --timeout=180s

# Remember the Deployment's UID: it has to be edited in place, not replaced.
kubectl -n "$NS" get deployment "$DEP" -o jsonpath='{.metadata.uid}' > "$LABDIR/x17.deploy.uid" 2>/dev/null || true
echo "$OLD_IMAGE" > "$LABDIR/x17.image" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Break the rollout.
#
# The pause comes first, so the controller never sees a changed template
# without the pause and never starts the new ReplicaSet.
# ---------------------------------------------------------------------------
kubectl -n "$NS" patch deployment "$DEP" --type=merge -p '{"spec":{"paused":true}}'
kubectl -n "$NS" patch deployment "$DEP" --type=merge \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"'"$DEP"'","image":"'"$NEW_IMAGE"'"}]}}}}'

# Give the controller a moment, then check that the pre-state is what the task
# describes: the Deployment wants to roll to the new image and cannot.
sleep 10

PAUSED=$(kubectl -n "$NS" get deployment "$DEP" -o jsonpath='{.spec.paused}' 2>/dev/null || true)
TEMPLATE_IMAGE=$(kubectl -n "$NS" get deployment "$DEP" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)
UPDATED=$(kubectl -n "$NS" get deployment "$DEP" -o jsonpath='{.status.updatedReplicas}' 2>/dev/null || true)
READY=$(kubectl -n "$NS" get deployment "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
STILL_OLD=$(kubectl -n "$NS" get pods -l "app=$DEP" -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' 2>/dev/null | grep -c "$OLD_IMAGE" || true)

echo "✅ x17 environment ready"
echo "   - namespace: $NS"
echo "   - Deployment: $DEP (3 replicas, pods labelled app=$DEP)"
echo "   - the pods are running $OLD_IMAGE and are ready: ${READY:-?}"
echo "   - pods still on $OLD_IMAGE: ${STILL_OLD:-0} of 3"
echo "   - the pod template asks for $NEW_IMAGE"
echo "   - the Deployment's rollout is stuck: updatedReplicas ${UPDATED:-0}, paused '${PAUSED:-false}'"
echo "   - Task: work out why the rollout cannot move and fix it, so that $NEW_IMAGE runs"
echo "     on all the replicas, without deleting the Deployment"

if [ "${PAUSED:-false}" != "true" ]; then
  echo "   ⚠️  The Deployment is not paused. Check:" >&2
  echo "      kubectl -n $NS get deploy $DEP -o jsonpath='{.spec.paused}'" >&2
fi
if [ "${TEMPLATE_IMAGE:-}" != "$NEW_IMAGE" ]; then
  echo "   ⚠️  The pod template does not ask for $NEW_IMAGE (it says '${TEMPLATE_IMAGE:-?}')." >&2
fi
if [ "${UPDATED:-0}" != "0" ]; then
  echo "   ⚠️  The Deployment has already rolled out ${UPDATED:-?} pods. Check:" >&2
  echo "      kubectl -n $NS get deploy $DEP" >&2
fi
if [ "${READY:-0}" != "3" ]; then
  echo "   ⚠️  The Deployment does not report 3 ready replicas yet. Check:" >&2
  echo "      kubectl -n $NS get pods -l app=$DEP" >&2
fi
