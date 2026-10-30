#!/bin/bash
set -e

# x19 - Two probes, both wrong
#
# The pre-state is a Deployment whose pods run but are never Ready, because
# the readiness probe points at a port nothing listens on, and whose
# containers the kubelet will eventually kill, because the liveness probe
# points at a path the server does not serve.
#
# The nginx configuration is mounted in rather than left at its default: the
# stock configuration answers every unknown path with the index page, so
# /healthz would return 200 and the liveness probe would never fail. This
# server answers exactly one path, so the probe behaves as the task says.

NS=probe
DEP=probed
CM=nginx-conf
LABDIR=/tmp/cka-lab

mkdir -p "$LABDIR"

# Start from a clean namespace every time.
kubectl delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
for i in $(seq 1 30); do
  kubectl get namespace "$NS" >/dev/null 2>&1 || break
  sleep 2
done

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

# A server that answers one path and 404s everything else.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: $CM
  namespace: $NS
data:
  nginx.conf: |
    user  nginx;
    worker_processes  auto;
    error_log  /var/log/nginx/error.log notice;
    pid        /var/run/nginx.pid;

    events {
        worker_connections  1024;
    }

    http {
        include       /etc/nginx/mime.types;
        default_type  application/octet-stream;
        access_log    /var/log/nginx/access.log;
        sendfile      on;
        keepalive_timeout  65;

        server {
            listen       80;
            server_name  _;

            # The only path this server answers.
            location = / {
                default_type text/plain;
                return 200 "ok\n";
            }

            # Everything else is a 404, so a probe pointed at /healthz fails.
            location / {
                return 404;
            }
        }
    }
EOF

# The Deployment under repair: two probes, both pointing at nothing.
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEP
  namespace: $NS
  labels:
    app: $DEP
spec:
  replicas: 2
  selector:
    matchLabels:
      app: $DEP
  template:
    metadata:
      labels:
        app: $DEP
    spec:
      containers:
        - name: nginx
          image: nginx:1.25
          command:
            - nginx
            - -c
            - /etc/nginx/cka/nginx.conf
            - -g
            - daemon off;
          ports:
            - name: http
              containerPort: 80
          volumeMounts:
            - name: conf
              mountPath: /etc/nginx/cka
              readOnly: true
          readinessProbe:
            tcpSocket:
              port: 8000
            periodSeconds: 5
            failureThreshold: 3
          livenessProbe:
            httpGet:
              path: /healthz
              port: 80
            initialDelaySeconds: 5
            periodSeconds: 10
            failureThreshold: 30
      volumes:
        - name: conf
          configMap:
            name: $CM
EOF

echo "Waiting for the pods to come up, but not to become Ready..."
RUNNING=0
READYREP=""
i=0
while [ "$i" -lt 120 ]; do
  RUNNING=$(kubectl -n "$NS" get pods -l "app=$DEP" \
              --field-selector=status.phase=Running \
              -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -c . || true)
  READYREP=$(kubectl -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null) || READYREP=""
  if [ "${RUNNING:-0}" -ge 2 ] 2>/dev/null && [ "${READYREP:-0}" -eq 0 ] 2>/dev/null; then break; fi
  sleep 2
  i=$((i+2))
done

# Remember the Deployment's UID: the pod template has to be edited in place,
# the Deployment must not be deleted and re-created.
kubectl -n "$NS" get deploy "$DEP" -o jsonpath='{.metadata.uid}' > "$LABDIR/x19.dep.uid" 2>/dev/null || true

echo "✅ x19 environment ready"
echo "   - namespace: $NS"
echo "   - Deployment: $DEP (nginx:1.25, 2 replicas, labels app=$DEP)"
echo "   - readinessProbe: tcpSocket on port 8000 - nothing listens there, so"
echo "     the pods are never Ready"
echo "   - livenessProbe: httpGet on port 80 path /healthz - the server does"
echo "     not serve it, so the kubelet will kill the containers in about"
echo "     5s + 10s x 30 = 305s"
echo "   - pods Running: ${RUNNING:-0}, ready replicas: ${READYREP:-0}"
echo "   - Task: fix both probes on the running Deployment - without deleting"
echo "     and re-creating it"

if [ "${RUNNING:-0}" -lt 2 ] 2>/dev/null || [ "${READYREP:-0}" -ne 0 ] 2>/dev/null; then
  echo "   ⚠️  The pods are not in the expected state. Check:" >&2
  echo "      kubectl -n $NS get pods -l app=$DEP" >&2
  echo "      kubectl -n $NS describe deployment $DEP" >&2
fi
