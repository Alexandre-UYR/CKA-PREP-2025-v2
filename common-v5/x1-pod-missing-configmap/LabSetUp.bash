#!/bin/bash
set -e

# x1 - The pod that will not start
#
# The pre-state is a Pod whose container sources an environment variable from
# a ConfigMap that does not exist. The kubelet cannot build the container's
# environment, so the Pod never starts - and the reason is written in the
# Pod's events, not in its status.
#
# The fix is to CREATE the missing ConfigMap. The Pod's spec is immutable in the
# field that matters here, so deleting and re-creating the Pod would be the
# wrong answer - and the grader checks the Pod's UID to prove it.

NS=diag
POD=web
CM=app-config
LABDIR=/tmp/cka-lab

mkdir -p "$LABDIR"

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

# A ConfigMap with a DIFFERENT name, so the namespace is not empty and the
# candidate has to read the event rather than assume the namespace is at fault.
kubectl -n "$NS" create configmap other-config --from-literal=MODE=prod \
  --dry-run=client -o yaml | kubectl apply -f -

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
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      envFrom:
        - configMapRef:
            name: $CM
EOF

echo "Waiting for the Pod to fail, so the pre-state is what the task describes..."
REASON=""
i=0
while [ "$i" -lt 60 ]; do
  REASON=$(kubectl -n "$NS" get pod "$POD" \
            -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null) || REASON=""
  case "$REASON" in
    CreateContainerConfigError|Error) break;;
  esac
  sleep 2
  i=$((i+2))
done

# Remember the Pod's UID: the fix must not involve re-creating it.
kubectl -n "$NS" get pod "$POD" -o jsonpath='{.metadata.uid}' > "$LABDIR/x1.pod.uid" 2>/dev/null || true

echo "✅ x1 environment ready"
echo "   - namespace: $NS"
echo "   - Pod: $POD (waiting reason: ${REASON:-<none yet>})"
echo "   - ConfigMap $CM: absent"
echo "   - ConfigMap other-config: present"
echo "   - Task: find out why the Pod will not start, and fix it without re-creating the Pod"

if [ "$REASON" != "CreateContainerConfigError" ] && [ "$REASON" != "Error" ]; then
  echo "   ⚠️  The Pod has not reported the expected waiting reason yet." >&2
  echo "      Check: kubectl -n $NS describe pod $POD" >&2
fi
