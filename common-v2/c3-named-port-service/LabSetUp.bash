#!/bin/bash
set -e

# Pre-state for c3: the namespace, and a Deployment whose container declares
# NO ports at all. The container port has to be added by the candidate -
# without it a Service that names its targetPort has nothing to point at.
#
# The Deployment is applied rather than created, so re-running the setup puts
# the clean, port-less state back.
NS=namedport

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: namedport
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
          image: nginx:1.25
EOF

echo "✅ c3 environment ready"
echo "   - namespace: $NS"
echo "   - Deployment: web (nginx:1.25, 1 replica, container declares no ports)"
echo "   - Task: name a container port and point a Service at it by name"
