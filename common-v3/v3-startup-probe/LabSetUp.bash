#!/bin/bash
set -e

# v3 - The app that is killed before it starts
#
# The pre-state is a Deployment whose container needs 60 seconds to start and
# carries a liveness probe against a port nothing listens on. The kubelet
# counts three failures and kills the container about 15 seconds in - long
# before the application has finished starting. The pod never becomes Ready.
#
# The namespace is recreated on every run, so the setup is idempotent and the
# starting state is always the same.

NS=probe
DEP=slow

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
          image: busybox:1.36
          command:
            - sh
            - -c
            - |
              sleep 60; sleep 3600
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 3
EOF

echo "Waiting for the kubelet to kill the container for the first time..."
RESTARTS=""
i=0
while [ "$i" -lt 90 ]; do
  RESTARTS=$(kubectl -n "$NS" get pods -l "app=$DEP" \
             -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}' 2>/dev/null) || RESTARTS=""
  [ -n "$RESTARTS" ] && [ "$RESTARTS" -ge 1 ] 2>/dev/null && break
  sleep 2
  i=$((i+2))
done

echo "✅ v3 environment ready"
echo "   - namespace: $NS"
echo "   - Deployment: $DEP (1 replica, busybox:1.36, container 'app')"
echo "   - the app needs 60 seconds to start: 'sleep 60; sleep 3600'"
echo "   - the liveness probe polls http://<pod>:8080/health, where nothing"
echo "     listens, so the kubelet kills the container about every 15 seconds"
echo "   - restarts so far: ${RESTARTS:-<none yet>}"
echo "   - Task: find the probe that is killing it, and let the container"
echo "     finish starting - and stay up afterwards"

if [ -z "$RESTARTS" ] || [ "$RESTARTS" -lt 1 ] 2>/dev/null; then
  echo "   ⚠️  The container has not been killed yet. Check the pod's events:" >&2
  echo "      kubectl -n $NS describe pod -l app=$DEP" >&2
fi
