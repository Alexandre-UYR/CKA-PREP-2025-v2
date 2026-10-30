#!/bin/bash
set -e

# Pre-state for c27: a Pod that is guaranteed to fall over.
#
# The break is `securityContext.readOnlyRootFilesystem: true` on a container
# whose command writes to /data. With a read-only root filesystem the
# `mkdir -p /data` fails with "Read-only file system", the container exits
# non-zero, and the kubelet restarts it with an increasing back-off. The Pod
# then sits in CrashLoopBackOff.
#
# The Pod's creationTimestamp is recorded in /tmp/cka-lab/c27.pod.before. A
# container's securityContext is immutable once the Pod exists, so the only
# way to fix this is to delete the Pod and create it again - and the
# grader proves that happened by comparing timestamps.

NS=broken
POD=worker
STATE=/tmp/cka-lab
BEFORE="$STATE/c27.pod.before"

mkdir -p "$STATE"

# Start from a clean pre-state. The Pod is re-created from scratch on every
# run, so its creationTimestamp is always fresh and always older than the one
# the candidate leaves behind.
kubectl delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n "$NS" -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: worker
  namespace: broken
spec:
  containers:
    - name: worker
      image: busybox:1.36
      command:
        - sh
        - -c
        - "mkdir -p /data && echo ok >> /data/app.log && sleep 3600"
      securityContext:
        readOnlyRootFilesystem: true
EOF

# Wait for the crash loop to establish itself, so the candidate meets the Pod
# already in CrashLoopBackOff rather than in its first restart.
i=0
LOOPING=0
while [ $i -lt 30 ]; do
  RC=$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || true)
  REASON=$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || true)
  case "${RC:-}" in ''|*[!0-9]*) RC=0;; esac
  if [ "$RC" -ge 1 ] && [ "$REASON" = "CrashLoopBackOff" ]; then LOOPING=1; break; fi
  i=$((i+1)); sleep 2
done

# Record the creationTimestamp of the broken Pod, so the grader can tell a
# re-created Pod from the one the setup put here.
kubectl -n "$NS" get pod "$POD" -o jsonpath='{.metadata.creationTimestamp}' > "$BEFORE"

echo "✅ c27 environment ready"
echo "   - namespace: $NS"
echo "   - Pod: $POD (busybox:1.36, securityContext.readOnlyRootFilesystem: true)"
if [ "$LOOPING" = "1" ]; then
  echo "   - the Pod is in CrashLoopBackOff"
else
  echo "   - WARNING: the Pod does not look like it is in CrashLoopBackOff yet"
  echo "   - WARNING: check 'kubectl -n $NS get pod $POD' and 'kubectl -n $NS logs $POD --previous'"
fi
echo "   - creationTimestamp recorded at: $BEFORE"
echo "   - Task: find out why the Pod keeps dying and fix it so it stays up"
