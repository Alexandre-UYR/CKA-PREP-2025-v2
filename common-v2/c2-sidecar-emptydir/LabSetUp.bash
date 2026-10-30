#!/bin/bash
set -e

# Pre-state for c2: the namespace, and a plain single-container Deployment.
#
# The Deployment is applied rather than created, so re-running the setup puts
# the clean one-container state back after a candidate has added the sidecar.
# `kubectl apply` recomputes the patch from the last-applied configuration,
# which means the candidate's extra container and extra volume are removed.
NS=sidecar

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
  namespace: sidecar
  labels:
    app: app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app
  template:
    metadata:
      labels:
        app: app
    spec:
      containers:
        - name: nginx
          image: nginx:1.25
EOF

echo "✅ c2 environment ready"
echo "   - namespace: $NS"
echo "   - Deployment: app (nginx:1.25, 1 replica, no volumes)"
echo "   - Task: add a busybox sidecar that shares an emptyDir with nginx"
