#!/bin/bash
set -e

# v4 — Bring a pod back from OOMKilled
#
# The pre-state is a Deployment whose container allocates far more memory than
# the cgroup limit allows. The kubelet kills it, the pod restarts it, and it
# dies again - which is what OOMKilled looks like from the outside.
#
# The namespace and the Deployment are recreated on every run so the setup is
# idempotent and the starting state is always the same.

NS=oom
DEP=greedy

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
          command: ["sh", "-c", "x=\$(yes | head -c 100000000); sleep 3600"]
          resources:
            requests:
              memory: 16Mi
            limits:
              memory: 32Mi
EOF

echo "Waiting for the container to be OOMKilled, so the pre-state is what the task describes..."
REASON=""
i=0
while [ "$i" -lt 60 ]; do
  REASON=$(kubectl -n "$NS" get pods -l "app=$DEP" \
            -o jsonpath='{.items[0].status.containerStatuses[0].lastState.terminated.reason}' 2>/dev/null) || REASON=""
  [ "$REASON" = "OOMKilled" ] && break
  sleep 2
  i=$((i+2))
done

echo "✅ v4 environment ready"
echo "   - namespace: $NS"
echo "   - Deployment: $DEP (memory limit 32Mi, request 16Mi)"
echo "   - last termination reason: ${REASON:-<none yet>}"
if [ "$REASON" != "OOMKilled" ]; then
  echo "   ⚠️  The container has not been OOMKilled yet. Check the pod's events:" >&2
  echo "      kubectl -n $NS describe pod -l app=$DEP" >&2
fi
echo "   - Task: find the real cause and make the pod stay running, with a limit it can live within"
