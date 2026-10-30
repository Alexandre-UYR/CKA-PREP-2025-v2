#!/bin/bash
set -e

# w3 - A Pod with two containers
#
# The pre-state is deliberately thin: a namespace and one healthy Deployment
# with a single container, there as a worked example of what one container
# looks like. The candidate has to build the two-container Pod themselves,
# with commands long enough that the Pod is still up five minutes later.

NS=multi
DEP=single

# Start from a clean namespace, so a Pod left over from a previous attempt
# cannot answer the validation on its own.
kubectl delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
i=0
while [ "$i" -lt 90 ]; do
  if ! kubectl get namespace "$NS" >/dev/null 2>&1; then
    break
  fi
  sleep 1
  i=$((i+1))
done
kubectl create namespace "$NS"

# The reference example: one container, running and Ready.
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
        - name: web
          image: nginx:1.16.0
          ports:
            - containerPort: 80
EOF

echo "Waiting for the example deployment to be available..."
kubectl -n "$NS" rollout status deployment/"$DEP" --timeout=180s

READY=$(kubectl -n "$NS" get deployment "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)

echo "✅ w3 environment ready"
echo "   - namespace: $NS"
echo "   - Deployment: $DEP (nginx:1.16.0, 1 replica, ready: ${READY:-?})"
echo "   - Task: create Pod 'multi-pod' with two containers, busy1 and busy2,"
echo "     both busybox:1.36 running 'sleep 100000', labelled env=test"

if [ "${READY:-0}" != "1" ]; then
  echo "   ⚠️  The example deployment is not ready. Check:" >&2
  echo "      kubectl -n $NS get pods" >&2
fi
