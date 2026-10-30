#!/bin/bash
set -e

# w1 - The deployment, its endpoints and its history
#
# The pre-state is a Deployment and a Service that already work. The task is
# about the OUTPUT: what the Service actually resolves to, and what the
# Deployment's rollout history says. Both are things you have to ask the
# cluster for in a particular format, and both are easy to get subtly wrong.

NS=cache
DEP=cache
SVC=cache
LABDIR=/tmp/cka-lab
OUT=/root

mkdir -p "$LABDIR"

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
        - name: memcached
          image: memcached
          ports:
            - containerPort: 11211
EOF

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: $SVC
  namespace: $NS
spec:
  type: NodePort
  selector:
    app: $DEP
  ports:
    - name: memcached
      port: 11211
      targetPort: 11211
      protocol: TCP
EOF

echo "Waiting for the deployment to be available..."
kubectl -n "$NS" rollout status deployment/"$DEP" --timeout=180s

# Remove anything a previous attempt left behind, so the question starts clean.
rm -f "$OUT/q3.json" "$OUT/q3.txt"

READY=$(kubectl -n "$NS" get deployment "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
NODEPORT=$(kubectl -n "$NS" get service "$SVC" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || true)

echo "✅ w1 environment ready"
echo "   - namespace: $NS"
echo "   - Deployment: $DEP (memcached, 3 replicas, ready: ${READY:-?})"
echo "   - Service: $SVC (NodePort ${NODEPORT:-?}, targetPort 11211)"
echo "   - Task: write the endpoints as JSON and the rollout history to a file, then scale"
