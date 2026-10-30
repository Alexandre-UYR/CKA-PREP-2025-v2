#!/bin/bash
set -e

# v1 - A log nobody can read
#
# The pre-state is a Deployment whose app container writes to /var/log/app.log
# with no volume mounted there. The file therefore lives in the container's own
# writable layer: no other container can see it, and it is gone every time the
# container restarts. There is no sidecar and no shared volume.
#
# The namespace is recreated on every run, so the setup is idempotent and the
# starting state is always the same.

NS=sidecar
DEP=web

kubectl delete namespace "$NS" --ignore-not-found --wait=true --timeout=120s >/dev/null 2>&1 || true
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

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
EOF

echo "Waiting for the app to write into the container's own filesystem..."
LINES=""
i=0
while [ "$i" -lt 60 ]; do
  LINES=$(kubectl -n "$NS" exec deploy/"$DEP" -c app -- cat /var/log/app.log 2>/dev/null) || LINES=""
  [ -n "$LINES" ] && break
  sleep 2
  i=$((i+2))
done

MOUNTS=$(kubectl -n "$NS" get deploy "$DEP" \
         -o jsonpath='{.spec.template.spec.containers[0].volumeMounts}' 2>/dev/null)

echo "✅ v1 environment ready"
echo "   - namespace: $NS"
echo "   - Deployment: $DEP (1 replica, nginx:1.25, container 'app')"
echo "   - the app writes to /var/log/app.log, but nothing is mounted there:"
echo "     the file lives in the container's own writable layer"
echo "   - log lines currently in that layer: $(printf '%s\n' "$LINES" | grep -c .)"
echo "   - Task: add a sidecar and a shared volume so the log is readable from"
echo "     another container and survives a restart"

if [ -z "$LINES" ]; then
  echo "   ⚠️  The app has not written a log line yet. Check the pod's events:" >&2
  echo "      kubectl -n $NS describe pod -l app=$DEP" >&2
fi

case "$MOUNTS" in
  *"/var/log"*)
    echo "   ⚠️  A volume is mounted at /var/log, so the pre-state is not what the" >&2
    echo "      task describes. Check the Deployment's volumeMounts." >&2
    ;;
esac
