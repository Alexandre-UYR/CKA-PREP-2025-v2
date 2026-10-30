#!/bin/bash
set -e

# v14 - Convert a legacy sidecar into a native one
#
# The pre-state is a Deployment whose log collector is a REGULAR container:
# it starts alongside the app, in an unspecified order, and cannot be
# restarted on its own. That is the legacy sidecar pattern, and the task is
# to convert it into a native sidecar - an initContainer with
# restartPolicy: Always.
#
# The namespace and the Deployment are recreated on every run so the setup is
# idempotent and the starting state is always the same.

NS=sidecars
DEP=legacy

kubectl delete namespace "$NS" --ignore-not-found --wait=true --timeout=120s >/dev/null 2>&1 || true
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

# The native sidecar field only exists from Kubernetes 1.28 onwards. Say so
# plainly if the server is older, because the task cannot be done there.
MAJOR=$(kubectl version -o jsonpath='{.serverVersion.major}' 2>/dev/null | tr -cd '0-9' || true)
MINOR=$(kubectl version -o jsonpath='{.serverVersion.minor}' 2>/dev/null | tr -cd '0-9' || true)
SERVER=""
if [ -n "$MAJOR" ] && [ -n "$MINOR" ]; then
  SERVER="$((10#$MAJOR * 100 + 10#$MINOR))"
fi

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEP
  namespace: $NS
  labels:
    app: $DEP
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $DEP
  template:
    metadata:
      labels:
        app: $DEP
    spec:
      containers:
        - name: app
          image: nginx:1.25
          command:
            - sh
            - -c
            - |
              while true; do echo "\$(date) app log line" >> /var/log/app.log; sleep 5; done
          volumeMounts:
            - name: shared-logs
              mountPath: /var/log
        - name: logcollector
          image: busybox:1.36
          command: ["sh", "-c", "tail -f /var/log/app.log"]
          volumeMounts:
            - name: shared-logs
              mountPath: /var/log
      volumes:
        - name: shared-logs
          emptyDir: {}
EOF

echo "Waiting for the pod to start, so the pre-state is a running legacy sidecar..."
READY=""
i=0
while [ "$i" -lt 90 ]; do
  READY=$(kubectl -n "$NS" get pods -l "app=$DEP" \
           -o jsonpath='{.items[0].status.containerStatuses[*].ready}' 2>/dev/null) || READY=""
  case "$READY" in
    *"true true"*) break;;
  esac
  sleep 2
  i=$((i+2))
done

echo "✅ v14 environment ready"
echo "   - namespace: $NS"
echo "   - Deployment: $DEP (1 replica, app=nginx:1.25, logcollector=busybox:1.36)"
echo "   - the logcollector is a REGULAR container in spec.containers: it starts"
echo "     alongside the app, in an unspecified order, and cannot be restarted alone"
echo "   - shared emptyDir 'shared-logs' mounted at /var/log in both containers"
if [ -n "$SERVER" ]; then
  echo "   - server version: $MAJOR.$MINOR"
else
  echo "   - server version: could not be read"
fi
echo "   - Task: move the logcollector into spec.initContainers with restartPolicy: Always"

if [ -n "$SERVER" ] && [ "$SERVER" -lt 128 ]; then
  echo "   ⚠️  This cluster is older than Kubernetes 1.28. The native sidecar field" >&2
  echo "      (an initContainer with restartPolicy: Always) does not exist there," >&2
  echo "      so the task cannot be completed on this server." >&2
elif [ -n "$SERVER" ] && [ "$SERVER" -eq 128 ]; then
  echo "   ⚠️  Kubernetes 1.28 has the field only behind the SidecarContainers" >&2
  echo "      feature gate. On 1.29 and newer it is enabled by default." >&2
fi
if [ "$READY" != "true true" ]; then
  echo "   ⚠️  The pod is not running with two ready containers yet. Check:" >&2
  echo "      kubectl -n $NS describe pod -l app=$DEP" >&2
fi
