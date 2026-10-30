#!/bin/bash
set -e

# w6 - Kill the old pods before you make the new ones
#
# The pre-state is a Deployment that works: 6 replicas of nginx:1.28, all
# ready, pods labelled app=proxy. Two things are wrong with it:
#
#   1. its strategy is the default RollingUpdate, so an update brings the new
#      pods up BEFORE the old ones go down;
#   2. the Deployment's own metadata carries no client=user label.
#
# The Deployment is deleted and recreated on every run, so the starting state
# is the same every time and the UID recorded here is the UID the candidate
# has to keep. If the previous attempt's answer file is lying around it is
# removed too, so a second run cannot pass on a stale answer.

NS=cka4
DEP=proxy
LABDIR=/tmp/cka-lab
OUT=/root
REPLICAS=6
IMAGE=nginx:1.28

mkdir -p "$LABDIR"

ensure_ns(){
  # Create the namespace, or bring back one that is still terminating.
  local ns=$1 phase i
  if kubectl get ns "$ns" >/dev/null 2>&1; then
    phase=$(kubectl get ns "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [ "$phase" = "Terminating" ]; then
      i=0
      while [ "$i" -lt 60 ]; do
        kubectl get ns "$ns" >/dev/null 2>&1 || break
        sleep 2
        i=$((i+2))
      done
    fi
  fi
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
}

ensure_ns "$NS"

# A previous attempt may have left a corrected Deployment behind. The
# pre-state is a Deployment with the DEFAULT strategy, so start from scratch
# rather than patching over whatever is there.
kubectl -n "$NS" delete deployment "$DEP" --ignore-not-found --wait=true --timeout=120s >/dev/null 2>&1 || true

# No `strategy:` key: the API server defaults it to RollingUpdate, which is
# exactly the state the question starts from.
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEP
  namespace: $NS
  labels:
    app: $DEP
spec:
  replicas: $REPLICAS
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
          image: $IMAGE
EOF

echo "Waiting for the deployment to be available..."
kubectl -n "$NS" rollout status deployment/"$DEP" --timeout=180s

# ---- record the state the validator needs -----------------------------------
# The UID is how the grader proves the Deployment was edited in place rather
# than deleted and recreated.

DEP_UID=$(kubectl -n "$NS" get deployment "$DEP" -o jsonpath='{.metadata.uid}' 2>/dev/null || true)
printf '%s\n' "$DEP_UID" > "$LABDIR/w6.dep.uid"

# Remove anything a previous attempt left behind, so the question starts clean.
rm -f "$OUT/q4.yaml"

STRATEGY=$(kubectl -n "$NS" get deployment "$DEP" -o jsonpath='{.spec.strategy.type}' 2>/dev/null || true)
ROLLING=$(kubectl -n "$NS" get deployment "$DEP" -o jsonpath='{.spec.strategy.rollingUpdate.maxUnavailable}' 2>/dev/null || true)
READY=$(kubectl -n "$NS" get deployment "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
CLIENT=$(kubectl -n "$NS" get deployment "$DEP" -o jsonpath='{.metadata.labels.client}' 2>/dev/null || true)
TMPLAPP=$(kubectl -n "$NS" get deployment "$DEP" -o jsonpath='{.spec.template.metadata.labels.app}' 2>/dev/null || true)

echo "✅ w6 environment ready"
echo "   - namespace: $NS"
echo "   - Deployment: $DEP ($IMAGE, ${REPLICAS:-?} replicas, ready: ${READY:-?})"
echo "   - strategy: ${STRATEGY:-<unknown>} (maxUnavailable ${ROLLING:-?})"
echo "   - the Deployment's own labels: client=${CLIENT:-<none>}"
echo "   - the pod template's labels: app=${TMPLAPP:-<none>}"
echo "   - Deployment UID: ${DEP_UID:-<unknown>} (recorded in $LABDIR/w6.dep.uid)"
echo "   - Task: make the update strategy kill the old pods before the new ones"
echo "     are created, put client=user on the Deployment itself, and save the"
echo "     corrected spec to $OUT/q4.yaml"

if [ "$STRATEGY" != "RollingUpdate" ]; then
  echo "   ⚠️  The strategy is '$STRATEGY' rather than the default RollingUpdate - the pre-state is not broken as described." >&2
  echo "      Check: kubectl -n $NS get deploy $DEP -o jsonpath='{.spec.strategy}'" >&2
fi
if [ -n "$CLIENT" ]; then
  echo "   ⚠️  The Deployment already carries a client label ('$CLIENT') - the pre-state is not broken as described." >&2
  echo "      Check: kubectl -n $NS get deploy $DEP -o jsonpath='{.metadata.labels}'" >&2
fi
