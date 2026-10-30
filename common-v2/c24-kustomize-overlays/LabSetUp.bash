#!/bin/bash
set -e

# Pre-state for c24: a Kustomize base with a Deployment and a Service.
#
# The base is rebuilt from scratch on every run, so a second attempt always
# starts from the same manifests.
#
# The `overlays` directory is NOT rebuilt. The candidate's overlays live
# there, and wiping them on every setup run would throw away the work they
# are being asked to do. The directory is only created when it is missing;
# the reset is what removes it.
ROOT=/tmp/cka-lab/kustomize
BASE="$ROOT/base"
OVERLAYS="$ROOT/overlays"

# Start from a clean cluster state: an `app` Deployment left in the cluster by
# a previous attempt would make the in-cluster part of the question
# meaningless. Only Deployments named `app` and labelled `app: app` are
# touched - that is the pair the base creates.
for ns in $(kubectl get deploy -A -l app=app -o jsonpath='{range .items[?(@.metadata.name=="app")]}{.metadata.namespace}{" "}{end}' 2>/dev/null || true); do
  kubectl -n "$ns" delete deploy app --ignore-not-found --wait=false >/dev/null 2>&1 || true
  kubectl -n "$ns" delete svc   app --ignore-not-found --wait=false >/dev/null 2>&1 || true
done

rm -rf "$BASE"
mkdir -p "$BASE"

cat > "$BASE/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml
EOF

cat > "$BASE/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
  labels:
    app: app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app
  template:
    metadata:
      labels:
        app: app
    spec:
      containers:
        - name: app
          image: nginx:1.24
          ports:
            - containerPort: 80
EOF

cat > "$BASE/service.yaml" <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: app
  labels:
    app: app
spec:
  type: ClusterIP
  selector:
    app: app
  ports:
    - name: http
      port: 80
      targetPort: 80
EOF

# The candidate's overlays are left alone; the directory is only created when
# it is not there yet.
if [ -d "$OVERLAYS" ]; then
  echo "   - the overlays directory was left in place (it holds the candidate's work)"
else
  mkdir -p "$OVERLAYS"
fi

echo "✅ c24 environment ready"
echo "   - base: $BASE (Deployment app, 2 replicas, nginx:1.24; Service app on port 80)"
echo "   - overlays directory: $OVERLAYS"
echo "   - Task: create the dev and prod overlays on top of the base, build"
echo "     each one and apply the dev overlay to the cluster"
