#!/bin/bash
set -e

# c9 starts from a Deployment with four replicas and no spread constraint at
# all: the candidate adds the constraint and scales the Deployment up. The
# Deployment is recreated every run, so the pre-state is the same whatever the
# last attempt left behind.

NS=topology
DEP=spread

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NS" delete deployment "$DEP" --ignore-not-found --wait=true >/dev/null

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spread
  namespace: topology
  labels:
    app: spread
spec:
  replicas: 4
  selector:
    matchLabels:
      app: spread
  template:
    metadata:
      labels:
        app: spread
    spec:
      containers:
        - name: nginx
          image: nginx:1.25
          resources:
            requests:
              cpu: 10m
              memory: 16Mi
EOF

kubectl -n "$NS" rollout status deployment/"$DEP" --timeout=180s

NODES=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | wc -l | tr -d ' ')
if [ "$NODES" -lt 2 ]; then
  echo "   WARNING: this cluster has $NODES node(s). A spread is only observable from two nodes up."
fi

echo "✅ c9 environment ready"
echo "   - namespace: $NS"
echo "   - Deployment $DEP: 4 replicas, image nginx:1.25, no topologySpreadConstraints"
echo "   - the Deployment was recreated, so it has none of a previous attempt's constraint"
echo "   - nodes in the cluster: $NODES"
echo "   - Task: add a topologySpreadConstraint to the pod template, then scale to 8 replicas"
