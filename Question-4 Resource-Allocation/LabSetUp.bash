#!/bin/bash
set -e
# setup-wordpress.sh
# Create a WordPress deployment with 3 replicas and an init container

# Remove any leftovers from a previous attempt: `kubectl apply` merges into the
# live object, so resource requests and limits that a previous candidate set on
# the pod template would survive and pollute the pre-state.
kubectl delete deployment wordpress --ignore-not-found --timeout=120s || true

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
spec:
  replicas: 3
  selector:
    matchLabels:
      app: wordpress
  template:
    metadata:
      labels:
        app: wordpress
    spec:
      initContainers:
      - name: init-setup
        image: busybox
        command: ["sh", "-c", "echo 'Preparing environment...' && sleep 5"]
      containers:
      - name: wordpress
        image: wordpress:6.2-apache
        ports:
        - containerPort: 80
EOF

echo "⏳ Waiting for the wordpress pods to be ready..."
kubectl wait --for=condition=Available deployment/wordpress --timeout=120s || \
  echo "   ⚠️  The deployment did not become Available in time; check the pods before starting the task." >&2
