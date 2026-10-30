#!/bin/bash
set -e

# w10 - Install a chart, and install it differently
#
# The pre-state is a local Helm chart on disk and nothing in the cluster:
# the candidate creates the namespace, installs the release, and then
# installs it again with a values file.
#
# The chart is built in a staging directory and then copied to two places:
#
#   /tmp/cka-lab/charts/hello-world            the working copy
#   /tmp/cka-lab/charts/.pristine-hello-world  the copy the reset restores
#
# The pristine copy is written from the staging directory, never copied from
# the working copy. If it were copied from the working copy, a candidate who
# had edited the chart would poison the pristine copy and the reset would
# restore their edit instead of the original chart.

NS=apps
RELEASE=hello
CHART_ROOT=/tmp/cka-lab/charts
WORK="$CHART_ROOT/hello-world"
PRISTINE="$CHART_ROOT/.pristine-hello-world"
STAGE=/tmp/cka-lab/.hello-world-staging
VALUES=/root/hello-values.yaml

mkdir -p "$CHART_ROOT"

# ---------------------------------------------------------------------------
# The chart
# ---------------------------------------------------------------------------

rm -rf "$STAGE"
mkdir -p "$STAGE/templates"

cat > "$STAGE/Chart.yaml" <<'EOF'
apiVersion: v2
name: hello-world
description: A minimal chart used by the CKA lab.
type: application
version: 1.0.0
appVersion: "1.25.0"
EOF

cat > "$STAGE/values.yaml" <<'EOF'
# The two values the chart's templates read. replicaCount is the one the
# candidate has to override from outside the chart; image is the one they
# must leave alone.
replicaCount: 1
image: nginx:1.25
EOF

cat > "$STAGE/templates/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Chart.Name }}
  labels:
    app: {{ .Chart.Name }}
    app.kubernetes.io/instance: {{ .Release.Name }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ .Chart.Name }}
  template:
    metadata:
      labels:
        app: {{ .Chart.Name }}
        app.kubernetes.io/instance: {{ .Release.Name }}
    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image }}"
          ports:
            - containerPort: 80
EOF

cat > "$STAGE/templates/service.yaml" <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: {{ .Chart.Name }}
  labels:
    app: {{ .Chart.Name }}
    app.kubernetes.io/instance: {{ .Release.Name }}
spec:
  selector:
    app: {{ .Chart.Name }}
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
EOF

# Copy it to the pristine and the working location. Both are written from
# the staging copy, so the pristine copy is untouched however much the
# candidate edits the working copy.
rm -rf "$PRISTINE" "$WORK"
cp -R "$STAGE" "$PRISTINE"
cp -R "$STAGE" "$WORK"
rm -rf "$STAGE"

# ---------------------------------------------------------------------------
# helm
# ---------------------------------------------------------------------------

if ! command -v helm >/dev/null 2>&1; then
  echo "WARNING: helm is not on the PATH, so this question cannot be done." >&2
  echo "         The chart is on disk at $WORK, but no namespace has been" >&2
  echo "         created and no release has been installed." >&2
  echo "         Install helm (3.x) and run the setup again." >&2
  exit 0
fi

# ---------------------------------------------------------------------------
# Clear anything a previous attempt left behind
# ---------------------------------------------------------------------------

# A release left over from a previous attempt would make `helm install hello`
# fail with "cannot re-use a name that is still in use".
if helm status "$RELEASE" -n "$NS" >/dev/null 2>&1; then
  helm uninstall "$RELEASE" -n "$NS" >/dev/null 2>&1 || true
fi
kubectl delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
rm -f "$VALUES"

echo "w10 environment ready"
echo "   - chart: $WORK (hello-world 1.0.0, appVersion 1.25.0)"
echo "   - the chart's own values.yaml: replicaCount 1, image nginx:1.25"
echo "   - pristine copy kept at: $PRISTINE"
echo "   - no namespace $NS, no release $RELEASE, no $VALUES"
echo "   - Task: create the namespace $NS, install the chart as the release"
echo "     $RELEASE, then install it again with a values file that sets"
echo "     replicaCount to 3, saved at $VALUES"
