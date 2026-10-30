#!/bin/bash
set -e

# w20 - One volume, two containers
#
# The pre-state is a Pod with one container that has already written a file
# into its emptyDir. The task is to put a second container in the same Pod,
# on the same volume, and read the file from there.

NS=shared
POD=writer
LABDIR=/tmp/cka-lab

mkdir -p "$LABDIR"

# Delete anything a previous attempt left behind, so the question starts clean.
kubectl delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
for i in $(seq 1 30); do
  kubectl get namespace "$NS" >/dev/null 2>&1 || break
  sleep 2
done

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $POD
  namespace: $NS
  labels:
    app: $POD
spec:
  containers:
    - name: writer
      image: busybox:1.36
      command: ["sh", "-c", "echo hello > /data/hi; sleep 10000"]
      volumeMounts:
        - name: work
          mountPath: /data
  volumes:
    - name: work
      emptyDir: {}
EOF

echo "Waiting for the pod to be running..."
for i in $(seq 1 60); do
  PHASE=$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  if [ "$PHASE" = "Running" ]; then break; fi
  sleep 2
done

# The point of the pre-state is the FILE, so wait until the file is really
# there rather than assuming the container started means it wrote it.
echo "Waiting for /data/hi to appear in the container..."
FOUND=""
for i in $(seq 1 30); do
  CONTENT=$(kubectl -n "$NS" exec "$POD" -c writer -- cat /data/hi 2>/dev/null | tr -d '\r\n' || true)
  if [ "$CONTENT" = "hello" ]; then
    FOUND=yes
    break
  fi
  sleep 2
done

if [ -n "$FOUND" ]; then
  echo "/data/hi exists and holds 'hello'."
else
  echo "WARNING: /data/hi never appeared in the container."
fi

MOUNTS=$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{range .spec.containers[0].volumeMounts[*]}{.name}@{.mountPath} {end}' 2>/dev/null || true)

echo "✅ w20 environment ready"
echo "   - namespace: $NS"
echo "   - Pod: $POD (busybox:1.36, one container, running)"
echo "   - volume mounts: $MOUNTS"
echo "   - /data/hi holds: $(kubectl -n "$NS" exec "$POD" -c writer -- cat /data/hi 2>/dev/null | tr -d '\r\n' || echo '?')"
echo "   - Task: add a second container to the Pod that mounts the same volume and reads /data/hi"
