#!/bin/bash
set -e

# Pre-state for c13: the namespace, two Deployments and the two Services the
# Ingress routes to.
#
# The Deployments and the Services are what make the Ingress meaningful - an
# Ingress that points at Services that select nothing is a valid object and a
# useless one. The label `app=a` / `app=b` on both the Deployment's pod
# template and the Service's selector is what ties each pair together.
NS=ingress

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-a
  namespace: ingress
  labels:
    app: a
spec:
  replicas: 1
  selector:
    matchLabels:
      app: a
  template:
    metadata:
      labels:
        app: a
    spec:
      containers:
        - name: nginx
          image: nginx:1.25
          ports:
            - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-b
  namespace: ingress
  labels:
    app: b
spec:
  replicas: 1
  selector:
    matchLabels:
      app: b
  template:
    metadata:
      labels:
        app: b
    spec:
      containers:
        - name: nginx
          image: nginx:1.25
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: app-a
  namespace: ingress
spec:
  selector:
    app: a
  ports:
    - name: http
      port: 80
      targetPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: app-b
  namespace: ingress
spec:
  selector:
    app: b
  ports:
    - name: http
      port: 80
      targetPort: 80
EOF

# Let the Deployments settle, so the pre-state is a working cluster and the
# Services have endpoints.
kubectl -n "$NS" rollout status deploy/app-a --timeout=120s || echo "WARNING: app-a did not become ready"
kubectl -n "$NS" rollout status deploy/app-b --timeout=120s || echo "WARNING: app-b did not become ready"

echo "✅ c13 environment ready"
echo "   - namespace: $NS"
echo "   - Deployments: app-a (app=a), app-b (app=b), 1 replica each, nginx:1.25"
echo "   - Services: app-a and app-b, both on port 80"
kubectl -n "$NS" get deploy,svc
echo "   - Task: create Ingress 'web' with two rules (shop.example.com and api.example.com)"
