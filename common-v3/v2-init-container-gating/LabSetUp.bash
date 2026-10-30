#!/bin/bash
set -e

# v2 - The app that cannot start
#
# The pre-state is a Deployment whose app container reads /etc/app/config.yaml
# and sleeps. There is no such file and no init container to produce one, so
# the container exits immediately and the pod sits in CrashLoopBackOff.
#
# The ConfigMap that holds the value is already there - the candidate has to
# wire it in, not invent it.
#
# The namespace is recreated on every run, so the setup is idempotent and the
# starting state is always the same.

NS=init
DEP=cfg

kubectl delete namespace "$NS" --ignore-not-found --wait=true --timeout=120s >/dev/null 2>&1 || true
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: $NS
data:
  config.yaml: |
    mode: production
---
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
              cat /etc/app/config.yaml && sleep 3600
EOF

echo "Waiting for the container to crash on the missing file..."
EXITCODE=""
i=0
while [ "$i" -lt 90 ]; do
  EXITCODE=$(kubectl -n "$NS" get pods -l "app=$DEP" \
             -o jsonpath='{.items[0].status.containerStatuses[0].lastState.terminated.exitCode}' 2>/dev/null) || EXITCODE=""
  [ -n "$EXITCODE" ] && break
  sleep 2
  i=$((i+2))
done

echo "✅ v2 environment ready"
echo "   - namespace: $NS"
echo "   - ConfigMap: app-config (key config.yaml)"
echo "   - Deployment: $DEP (1 replica, nginx:1.25, container 'app')"
echo "   - the app reads /etc/app/config.yaml, which does not exist, and exits"
echo "   - no volumes and no init containers are defined"
echo "   - last container exit code: ${EXITCODE:-<none yet>}"
echo "   - Task: add an init container that produces the file, and mount it"
echo "     into the main container"

if [ -z "$EXITCODE" ]; then
  echo "   ⚠️  The container has not crashed yet. Check the pod's events:" >&2
  echo "      kubectl -n $NS describe pod -l app=$DEP" >&2
fi
