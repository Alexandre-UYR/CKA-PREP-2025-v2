#!/bin/bash
set -e

# Pre-state for c23: the namespace the task names, the `helm` binary the task
# needs, and a local chart whose Deployment points at an image tag that does
# not exist.
#
# The chart is generated into a staging directory and then copied to two
# places:
#
#   /tmp/cka-lab/charts/broken-chart            the working copy the candidate edits
#   /tmp/cka-lab/charts/.pristine-broken-chart  the untouched copy the reset restores
#
# The pristine copy is written from the staging directory, never copied from
# the working copy. If it were copied from the working copy, a candidate who
# had already fixed the chart would poison the pristine copy and the reset
# would restore their fix instead of the fault.
NS=webapps
RELEASE=broken
CHARTS=/tmp/cka-lab/charts
WORK="$CHARTS/broken-chart"
PRISTINE="$CHARTS/.pristine-broken-chart"
STAGE=/tmp/cka-lab/.chart-staging

if ! command -v helm >/dev/null 2>&1; then
  echo "helm is not on the PATH - this question needs helm to be installed" >&2
  exit 1
fi

mkdir -p "$CHARTS"

# Start from a clean pre-state. A release left over from a previous attempt
# would make `helm install` fail with "cannot re-use a name that is still in
# use", and the namespace has to exist before the chart can be installed.
if helm status "$RELEASE" -n "$NS" >/dev/null 2>&1; then
  helm uninstall "$RELEASE" -n "$NS" >/dev/null 2>&1 || true
fi
kubectl delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

# Build the chart in a staging directory...
rm -rf "$STAGE"
mkdir -p "$STAGE/templates"

cat > "$STAGE/Chart.yaml" <<'EOF'
apiVersion: v2
name: broken-chart
description: A chart whose Deployment points at an image tag that does not exist.
type: application
version: 0.1.0
appVersion: "1.0"
EOF

cat > "$STAGE/values.yaml" <<'EOF'
replicaCount: 1

service:
  type: ClusterIP
  port: 80

# The container image is not parameterised here on purpose: it is hard-coded
# in templates/deployment.yaml, so the fault can only be fixed by editing the
# template itself.
EOF

cat > "$STAGE/templates/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: broken-chart
  labels:
    app.kubernetes.io/name: broken-chart
    app.kubernetes.io/instance: {{ .Release.Name }}
    app.kubernetes.io/managed-by: {{ .Release.Service }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app.kubernetes.io/name: broken-chart
      app.kubernetes.io/instance: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: broken-chart
        app.kubernetes.io/instance: {{ .Release.Name }}
    spec:
      containers:
        - name: broken-chart
          image: nginx:0.0.0-does-not-exist
          ports:
            - containerPort: 80
EOF

# ... and copy it to the pristine and the working location. Both are written
# from the staging copy, so the pristine copy is broken however much the
# candidate has edited the working copy.
rm -rf "$PRISTINE" "$WORK"
cp -R "$STAGE" "$PRISTINE"
cp -R "$STAGE" "$WORK"
rm -rf "$STAGE"

echo "✅ c23 environment ready"
echo "   - namespace: $NS"
echo "   - chart: $WORK"
echo "   - the chart's Deployment 'broken-chart' asks for nginx:0.0.0-does-not-exist"
echo "   - Task: helm install $RELEASE $WORK -n $NS, find the fault, fix the"
echo "     chart, upgrade the release and get the pod Running"
