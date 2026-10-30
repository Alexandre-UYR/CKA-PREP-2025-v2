#!/bin/bash
set -e

# w15 - The overlay that does nothing
#
# The pre-state is a Kustomize base and an overlay that patches a resource
# which does not exist in the base. `kubectl kustomize` on that overlay
# succeeds and prints the base unchanged, so the failure looks like "my patch
# had no effect" rather than an error.
#
# The base is kept in two places:
#
#   /tmp/cka-lab/kustomize/base             the working copy the candidate uses
#   /tmp/cka-lab/kustomize/.pristine-base   the untouched copy the reset restores
#
# The pristine copy is written from the staging directory and never copied
# from the working copy: if it were, a candidate who had already edited the
# base would poison the pristine copy and the reset would restore their edit
# instead of the original base.
#
# The overlays directory is rebuilt on every run, but ONLY the dev overlay:
# a `prod` overlay the candidate has created is left alone.

ROOT=/tmp/cka-lab/kustomize
STAGE=/tmp/cka-lab/.kustomize-staging
BASE="$ROOT/base"
PRISTINE="$ROOT/.pristine-base"
OVERLAYS="$ROOT/overlays"
DEV="$OVERLAYS/dev"

# Anything the candidate applied in an earlier attempt has to go, so the
# cluster starts from the same state as the disk.
kubectl delete namespace dev --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

rm -rf "$STAGE"
mkdir -p "$STAGE/base" "$STAGE/overlays/dev"

# ---------------------------------------------------------------------------
# The base
# ---------------------------------------------------------------------------

cat > "$STAGE/base/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml
EOF

cat > "$STAGE/base/deployment.yaml" <<'EOF'
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

cat > "$STAGE/base/service.yaml" <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: app
  labels:
    app: app
spec:
  selector:
    app: app
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
EOF

# ---------------------------------------------------------------------------
# The dev overlay - broken on purpose
#
# The patch names a Deployment called `worker`. The base has no such
# resource, so the patch is dropped and the overlay builds to the base
# unchanged: nginx:1.24, 2 replicas.
# ---------------------------------------------------------------------------

cat > "$STAGE/overlays/dev/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: dev

resources:
  - ../../base

patchesStrategicMerge:
  - patch-deployment.yaml
EOF

cat > "$STAGE/overlays/dev/patch-deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: worker
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: app
          image: nginx:1.25
EOF

# ---------------------------------------------------------------------------
# Put it in place
# ---------------------------------------------------------------------------

mkdir -p "$ROOT" "$OVERLAYS"

rm -rf "$PRISTINE" "$BASE"
cp -R "$STAGE/base" "$PRISTINE"
cp -R "$STAGE/base" "$BASE"

# Only the dev overlay is replaced. A prod overlay the candidate has written
# stays where it is.
rm -rf "$DEV"
mkdir -p "$DEV"
cp "$STAGE/overlays/dev/kustomization.yaml" "$DEV/kustomization.yaml"
cp "$STAGE/overlays/dev/patch-deployment.yaml" "$DEV/patch-deployment.yaml"

rm -rf "$STAGE"

# Prove the pre-state is the one the task describes: the dev overlay does not
# produce the Deployment it is supposed to.
BUILT=""
BUILDRC=0
if command -v kubectl >/dev/null 2>&1; then
  BUILT=$(kubectl kustomize "$DEV" 2>/dev/null) || BUILDRC=1
fi
if [ "$BUILDRC" -ne 0 ]; then
  echo "   the dev overlay does not build: kubectl kustomize stops with an error"
  echo "   (the build says what is wrong - read it: kubectl kustomize $DEV)"
elif [ -z "$BUILT" ]; then
  echo "   WARN: kubectl kustomize did not build the dev overlay. Check:" >&2
  echo "      kubectl kustomize $DEV" >&2
elif printf '%s' "$BUILT" | grep -q 'nginx:1.25'; then
  echo "   WARN: the dev overlay is not broken - it already changes the image." >&2
else
  echo "   the dev overlay builds, and changes nothing: image nginx:1.24, 2 replicas"
fi

echo "✅ w15 environment ready"
echo "   - base:    $BASE  (Deployment app, 2 replicas, nginx:1.24; Service app on port 80)"
echo "   - overlay: $DEV  (its patch does not do what it is meant to)"
echo "   - Task: make the dev overlay produce nginx:1.25 / 1 replica in namespace dev,"
echo "     write a prod overlay (nginx:1.26 / 3 replicas / NodePort Service),"
echo "     build both with kubectl kustomize and apply the dev one"
