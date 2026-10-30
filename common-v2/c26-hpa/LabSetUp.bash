#!/bin/bash
set -e

# Pre-state for c26: the namespace the task names, and the Deployment the HPA
# is supposed to point at.
#
# The Deployment's UID is recorded in /tmp/cka-lab/c26.uid. The task says not
# to re-create the Deployment, and the grader checks that by comparing the
# UID: a candidate who deleted `web` and applied it again has thrown away the
# workload the lab gave them, even though the HPA object ends up looking
# right.
#
# The Deployment is deleted and re-applied on every run, so the pre-state is
# always the same: same replica count, same image, same resources, and a UID
# that matches the one recorded below.

NS=autoscale
DEPLOY=web
UID_FILE=/tmp/cka-lab/c26.uid

mkdir -p /tmp/cka-lab

kubectl delete deployment "$DEPLOY" -n "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n "$NS" -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: autoscale
  labels:
    app: web
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: web
          image: nginx
          resources:
            requests:
              cpu: 100m
            limits:
              cpu: 200m
EOF

# Record the UID of the Deployment that is in the cluster right now.
kubectl -n "$NS" get deployment "$DEPLOY" -o jsonpath='{.metadata.uid}' > "$UID_FILE"

# The grader reads the HPA spec, not the replica count, so a slow image pull
# is not fatal here. Wait a little anyway so the workload has a chance to come
# up before the candidate starts.
kubectl rollout status deployment "$DEPLOY" -n "$NS" --timeout=120s >/dev/null 2>&1 || true

echo "✅ c26 environment ready"
echo "   - namespace: $NS"
echo "   - Deployment: $DEPLOY (image nginx, 2 replicas, requests.cpu 100m, limits.cpu 200m)"
echo "   - Deployment UID recorded at: $UID_FILE"
echo "   - Task: create a HorizontalPodAutoscaler 'web-hpa' targeting the 'web' Deployment"
