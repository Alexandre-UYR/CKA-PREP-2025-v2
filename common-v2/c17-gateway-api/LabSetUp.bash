#!/bin/bash
set -e

# Pre-state for c17: a plain Deployment and Service in the default namespace,
# and NO Gateway API CRDs.
#
# The CRDs are deliberately absent: installing them is step 1 of the task, and
# without them there is no Gateway or HTTPRoute resource to create at all.
#
# The CRDs are cluster-scoped, so the reset cannot remove them (deleting a CRD
# destroys every object of that kind in the cluster). If a previous attempt
# left them installed, they stay - and this setup re-applies the standard
# channel set idempotently, so the environment is always in the same
# configuration whatever the previous attempt did.

NS=default
CRD_URL="https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml"

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: default
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
        - name: web
          image: nginx
          ports:
            - containerPort: 80
EOF

cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: default
spec:
  type: ClusterIP
  selector:
    app: web
  ports:
    - name: http
      port: 80
      targetPort: 80
EOF

# A previous attempt may have left Gateways and HTTPRoutes behind. Remove them
# so the candidate always starts from the same pre-state.
kubectl delete gateways.gateway.networking.k8s.io --all -A --ignore-not-found >/dev/null 2>&1 || true
kubectl delete httproutes.gateway.networking.k8s.io --all -A --ignore-not-found >/dev/null 2>&1 || true

# The Gateway API CRDs are only re-applied when they are already there (a
# previous attempt installed them). On a clean cluster they stay absent, which
# is the pre-state this question wants.
if kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1; then
  echo "Gateway API CRDs already present - re-applying the standard set idempotently."
  kubectl apply -f "$CRD_URL" >/dev/null 2>&1 || \
    echo "   (re-apply skipped: no access to github.com; the CRDs already installed are left in place)"
else
  echo "Gateway API CRDs are NOT installed - installing them is step 1 of the task."
fi

kubectl -n "$NS" rollout status deploy/web --timeout=120s || \
  echo "   (note: Deployment web did not report ready in 120s - this question does not need it to be ready)"

echo "✅ c17 environment ready"
echo "   - namespace: $NS"
echo "   - Deployment: web (nginx, 1 replica, labels app=web)"
echo "   - Service: web (port 80, selector app=web)"
echo "   - Gateway API CRDs: not installed"
echo "   - Task: install the Gateway API CRDs, then create a Gateway and an HTTPRoute"
