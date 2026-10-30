#!/bin/bash
set -e

# Pre-state for c15: a namespace and a Deployment with nothing in front of it.
#
# The three Services are the answer, so the setup does not create any. The
# Deployment carries the label `app=web`, which is what the candidate's
# Services have to select in order to get endpoints.
NS=svctypes

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: svctypes
  labels:
    app: web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: nginx
          image: nginx
          ports:
            - containerPort: 80
EOF

# A Service only gets endpoints once its pods are ready, so wait for the
# rollout. A failure here is a broken pre-state, not a wrong answer.
kubectl -n "$NS" rollout status deploy/web --timeout=120s \
  || echo "   warning: the web deployment is not ready yet"

echo "✅ c15 environment ready"
echo "   - namespace: $NS"
echo "   - Deployment: web (nginx, 1 replica, labels app=web)"
echo "   - Task: expose it three ways - ClusterIP, NodePort and LoadBalancer"
