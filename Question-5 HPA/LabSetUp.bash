#!/bin/bash
set -e

echo "🔹 Creating namespace..."
kubectl create namespace autoscale --dry-run=client -o yaml | kubectl apply -f -

echo "🔹 Deploying metrics-server (required for HPA)..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

echo "🔹 Patching metrics-server to allow insecure TLS (Killercoda environment)..."
# The JSON patch below APPENDS to the args array, so running setup twice would
# add --kubelet-insecure-tls twice. Only patch when the flag is not there yet.
if kubectl get deployment metrics-server -n kube-system -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null | grep -q -- '--kubelet-insecure-tls'; then
  echo "   --kubelet-insecure-tls already present, skipping patch."
else
  kubectl patch deployment metrics-server -n kube-system \
    --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]' || true
fi

echo "🔹 Waiting for metrics-server rollout..."
kubectl rollout status deployment metrics-server -n kube-system

echo "🔹 Creating Apache deployment..."
kubectl apply -n autoscale -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: apache-deployment
  namespace: autoscale
spec:
  replicas: 1
  selector:
    matchLabels:
      app: apache
  template:
    metadata:
      labels:
        app: apache
    spec:
      containers:
      - name: apache
        image: httpd
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
          limits:
            cpu: 200m
EOF

echo "🔹 Exposing Apache deployment internally..."
# dry-run + apply so a second run of setup does not fail on "already exists".
kubectl expose deployment apache-deployment -n autoscale --port=80 --target-port=80 --dry-run=client -o yaml | kubectl apply -f -

echo "✅ HPA lab setup complete."
echo "   - Namespace: autoscale"
echo "   - Deployment: apache-deployment"
echo "   - Service: apache-deployment"
echo "You can now create your HPA resource."
