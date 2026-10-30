#!/bin/bash
set -e

# v19 - Overriding a subchart's values
#
# The pre-state is a local Helm chart with a subchart: a parent chart `stack`
# whose values.yaml holds the frontend's settings and a `backend:` section,
# and a `backend` subchart vendored under charts/.
#
# The chart is built in a staging directory and then copied to two places:
#
#   /tmp/cka-lab/charts/stack            the working copy the candidate uses
#   /tmp/cka-lab/charts/.pristine-stack  the untouched copy the reset restores
#
# The pristine copy is written from the staging directory, never copied from
# the working copy. If it were copied from the working copy, a candidate who
# had already edited the chart would poison the pristine copy and the reset
# would restore their edit instead of the original chart.
#
# The chart is local on purpose: the lab must not depend on a public
# repository, on network access, or on what some remote index happens to
# contain today.

NS=apps
RELEASE=stack
CHART_ROOT=/tmp/cka-lab/charts
WORK="$CHART_ROOT/stack"
PRISTINE="$CHART_ROOT/.pristine-stack"
STAGE=/tmp/cka-lab/.stack-staging
VALUES=/tmp/cka-lab/stack-values.yaml

if ! command -v helm >/dev/null 2>&1; then
  echo "⚠️  helm is not on the PATH - this question cannot be done without it." >&2
  echo "    Install helm (3.x) and run the setup again; nothing has been created." >&2
  exit 0
fi

mkdir -p "$CHART_ROOT"

# Start from a clean pre-state. A release left over from a previous attempt
# would make `helm install` fail with "cannot re-use a name that is still in
# use", and the candidate has to create the namespace itself.
if helm status "$RELEASE" -n "$NS" >/dev/null 2>&1; then
  helm uninstall "$RELEASE" -n "$NS" >/dev/null 2>&1 || true
fi
kubectl delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
rm -f "$VALUES"

# ---------------------------------------------------------------------------
# The parent chart
# ---------------------------------------------------------------------------

rm -rf "$STAGE"
mkdir -p "$STAGE/templates" "$STAGE/charts/backend/templates"

cat > "$STAGE/Chart.yaml" <<'EOF'
apiVersion: v2
name: stack
description: A parent chart with one subchart.
type: application
version: 1.0.0
appVersion: "1.0.0"
dependencies:
  - name: backend
    version: 0.1.0
    repository: "file://charts/backend"
EOF

cat > "$STAGE/values.yaml" <<'EOF'
# The frontend belongs to the parent chart.
frontend:
  image:
    repository: nginx
    tag: "1.0.0"
  replicas: 1
  service:
    port: 80

# The backend is a subchart. Its values live under the subchart's own key,
# and this section overrides the subchart's own values.yaml.
backend:
  image:
    repository: nginx
    tag: "1.0.0"
  replicas: 1
  service:
    port: 8080
EOF

cat > "$STAGE/templates/frontend-deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  labels:
    app: frontend
    app.kubernetes.io/instance: {{ .Release.Name }}
spec:
  replicas: {{ .Values.frontend.replicas }}
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
        app.kubernetes.io/instance: {{ .Release.Name }}
    spec:
      containers:
        - name: frontend
          image: "{{ .Values.frontend.image.repository }}:{{ .Values.frontend.image.tag }}"
          ports:
            - containerPort: {{ .Values.frontend.service.port }}
EOF

cat > "$STAGE/templates/frontend-service.yaml" <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: frontend
  labels:
    app: frontend
    app.kubernetes.io/instance: {{ .Release.Name }}
spec:
  selector:
    app: frontend
  ports:
    - port: {{ .Values.frontend.service.port }}
      targetPort: {{ .Values.frontend.service.port }}
EOF

# ---------------------------------------------------------------------------
# The backend subchart, vendored under charts/
# ---------------------------------------------------------------------------

cat > "$STAGE/charts/backend/Chart.yaml" <<'EOF'
apiVersion: v2
name: backend
description: The backend subchart.
type: application
version: 0.1.0
appVersion: "1.0.0"
EOF

cat > "$STAGE/charts/backend/values.yaml" <<'EOF'
image:
  repository: nginx
  tag: "1.0.0"
replicas: 1
service:
  port: 8080
EOF

cat > "$STAGE/charts/backend/templates/backend-deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  labels:
    app: backend
    app.kubernetes.io/instance: {{ .Release.Name }}
spec:
  replicas: {{ .Values.replicas }}
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
        app.kubernetes.io/instance: {{ .Release.Name }}
    spec:
      containers:
        - name: backend
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          ports:
            - containerPort: {{ .Values.service.port }}
EOF

cat > "$STAGE/charts/backend/templates/backend-service.yaml" <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: backend
  labels:
    app: backend
    app.kubernetes.io/instance: {{ .Release.Name }}
spec:
  selector:
    app: backend
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.port }}
EOF

# Copy it to the pristine and the working location. Both are written from
# the staging copy, so the pristine copy is untouched however much the
# candidate edits the working copy.
rm -rf "$PRISTINE" "$WORK"
cp -R "$STAGE" "$PRISTINE"
cp -R "$STAGE" "$WORK"
rm -rf "$STAGE"

echo "✅ v19 environment ready"
echo "   - chart: $WORK"
echo "   - parent chart: stack 1.0.0, with the subchart 'backend' vendored under charts/"
echo "   - defaults: frontend image tag 1.0.0 / 1 replica / service port 80"
echo "              backend  image tag 1.0.0 / 1 replica / service port 8080"
echo "   - the values file the candidate has to write: $VALUES"
echo "   - Task: install the chart as the release 'stack' in namespace '$NS'"
echo "     with the frontend on tag 2.1.0 and 3 replicas, and the backend"
echo "     subchart on tag 2.0.5, 2 replicas and service port 9090"
