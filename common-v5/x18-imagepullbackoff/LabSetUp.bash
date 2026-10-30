#!/bin/bash
set -e

# x18 - The tag that does not exist
#
# The pre-state is a Pod whose image reference names a tag that is not in the
# registry. The kubelet cannot pull it, so the Pod sits in ImagePullBackOff -
# and the reason the pull failed is in the Pod's events, not in the status.
#
# The ConfigMap image-tags is the source of truth for which tags exist. It
# must not be changed: the grader compares the live ConfigMap with the copy
# taken here.

NS=reg
POD=app
CM=image-tags
LABDIR=/tmp/cka-lab

mkdir -p "$LABDIR"

# Start from a clean namespace every time, so a Pod left over from an earlier
# attempt cannot answer the validation.
kubectl delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
for i in $(seq 1 30); do
  kubectl get namespace "$NS" >/dev/null 2>&1 || break
  sleep 2
done

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

# The tags that DO exist. One key per image; the value is the space-separated
# list of that image's tags.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: $CM
  namespace: $NS
data:
  nginx: "1.25 1.26"
EOF

# The Pod names a tag that is not in that list, and that does not exist in the
# registry either, so the pull fails.
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
      image: nginx:1.99
      command: ["sleep", "10000"]
EOF

echo "Waiting for the kubelet to fail the pull..."
REASON=""
i=0
while [ "$i" -lt 120 ]; do
  REASON=$(kubectl -n "$NS" get pod "$POD" \
            -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null) || REASON=""
  case "$REASON" in
    ImagePullBackOff) break;;
  esac
  sleep 2
  i=$((i+2))
done

# Remember what the ConfigMap said, so the grader can prove it was not
# edited to make the Pod's image look right.
kubectl -n "$NS" get cm "$CM" \
  -o go-template='{{range $k, $v := .data}}{{$k}}={{$v}}{{"\n"}}{{end}}' \
  > "$LABDIR/x18.cm.data" 2>/dev/null || true

echo "✅ x18 environment ready"
echo "   - namespace: $NS"
echo "   - Pod: $POD (image nginx:1.99, waiting reason: ${REASON:-<none yet>})"
echo "   - ConfigMap $CM: nginx -> 1.25 1.26"
echo "   - Task: find out which part of the image reference is wrong, and fix"
echo "     the Pod so that it starts - without changing the ConfigMap"

if [ "$REASON" != "ImagePullBackOff" ]; then
  echo "   ⚠️  The Pod has not reported ImagePullBackOff yet. Check:" >&2
  echo "      kubectl -n $NS describe pod $POD" >&2
fi
