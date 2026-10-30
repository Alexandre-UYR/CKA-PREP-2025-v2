#!/bin/bash
set -e

# v9 - Protect the workload from voluntary disruption
#
# The pre-state is a healthy three-replica Deployment with nothing standing
# between it and a node drain. `kubectl -n pdb get pdb` is empty: the workload
# can lose all three pods at once.
#
# The namespace and the Deployment are recreated on every run, so the setup is
# idempotent and the starting state is always the same.

NS=pdb
DEP=api
IMAGE=nginx:1.25
REPLICAS=3

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
        - name: web
          image: $IMAGE
EOF

echo "Waiting for the $DEP pods to become ready, so the pre-state is a healthy workload..."
READY=""
i=0
while [ "$i" -lt 90 ]; do
  READY=$(kubectl -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
  [ "$READY" = "$REPLICAS" ] && break
  sleep 2
  i=$((i+2))
done

PDBS=$(kubectl -n "$NS" get pdb --no-headers 2>/dev/null | grep -c . | tr -d ' ')

echo "✅ v9 environment ready"
echo "   - namespace: $NS"
echo "   - Deployment: $DEP (image $IMAGE, $REPLICAS replicas, labels app=$DEP)"
echo "   - ready replicas: ${READY:-0}/$REPLICAS"
echo "   - PodDisruptionBudgets in the namespace: ${PDBS:-0}"
echo "   - Task: write a budget that lets the API server evict at most one of these pods at a time"

if [ "$READY" != "$REPLICAS" ]; then
  echo "   ⚠️  Only ${READY:-0} of $REPLICAS replicas are ready. Check:" >&2
  echo "      kubectl -n $NS get pods" >&2
  echo "      kubectl -n $NS describe deploy $DEP" >&2
fi
