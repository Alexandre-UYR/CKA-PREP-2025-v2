#!/bin/bash
set -e

echo "🚀 Setting up WordPress deployment for sidecar lab in the default namespace..."

# 0. Remove any leftovers from a previous attempt, so the pre-state is always
#    the single-container deployment the task describes. `kubectl apply` would
#    otherwise keep fields that a previous candidate added to the pod template.
kubectl delete deployment wordpress --ignore-not-found --timeout=60s || true
kubectl delete service wordpress --ignore-not-found --timeout=60s || true

# 1. Create WordPress deployment without log volume
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  labels:
    app: wordpress
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wordpress
  template:
    metadata:
      labels:
        app: wordpress
    spec:
      containers:
      - name: wordpress
        image: wordpress:php8.2-apache
        command: ["/bin/sh", "-c", "while true; do echo 'WordPress is running...' >> /var/log/wordpress.log; sleep 5; done"]
        ports:
        - containerPort: 80
EOF

# 2. Create a service to expose the deployment
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: wordpress
spec:
  selector:
    app: wordpress
  ports:
  - port: 80
    targetPort: 80
EOF

# 3. Wait for the pod to actually run, so the pre-state is a healthy workload
#    and the log file already exists.
echo "⏳ Waiting for the wordpress pod to be ready..."
if kubectl wait --for=condition=Available deployment/wordpress --timeout=120s; then
  echo "   WordPress is running."
else
  echo "   ⚠️  The wordpress deployment did not become Available in time." >&2
  echo "      Check the pod before starting the task." >&2
fi

# 4. The UID of the deployment as it exists right now. The task says to UPDATE
#    the existing deployment, so the grader compares this UID with the UID at
#    validation time: a re-created deployment has a different UID.
mkdir -p /tmp/cka-lab
kubectl get deploy wordpress -o jsonpath='{.metadata.uid}' > /tmp/cka-lab/q3.deploy.uid

echo
echo "✅ Lab setup complete!"
echo
echo "WordPress deployment created in the default namespace."
echo "You can now edit the deployment to add the sidecar container and shared volume."
