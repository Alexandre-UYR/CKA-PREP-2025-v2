#!/bin/bash
set -e

# w19 - Reachable, but only once it is ready
#
# The pre-state is a healthy Deployment with no probe and no Service. The task
# is to publish it on a NodePort and then make the "ready" part real with a
# readiness probe, which is what the endpoints controller keys off.

NS=edge
DEP=catalog
SVC=catalog-svc
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
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEP
  namespace: $NS
  labels:
    app: $DEP
spec:
  replicas: 2
  selector:
    matchLabels:
      app: $DEP
  template:
    metadata:
      labels:
        app: $DEP
    spec:
      containers:
        - name: nginx
          image: nginx:1.25
          ports:
            - containerPort: 80
              protocol: TCP
EOF

echo "Waiting for the deployment to be available..."
kubectl -n "$NS" rollout status deployment/"$DEP" --timeout=180s

# The pre-state must not already have a probe, or there is nothing to add.
PROBE=$(kubectl -n "$NS" get deployment "$DEP" -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}' 2>/dev/null || true)
if [ -z "$PROBE" ]; then
  echo "The deployment has no readiness probe, as it should."
else
  echo "WARNING: the deployment already has a readiness probe ($PROBE)."
fi

# Warn early if the nodePort the task fixes is already taken, so a candidate
# is not left guessing why their Service will not create.
if kubectl get svc --all-namespaces --no-headers \
     -o custom-columns='NAME:.metadata.name,PORTS:.spec.ports[*].nodePort' 2>/dev/null \
   | grep -q '30080'; then
  echo "WARNING: nodePort 30080 is already in use by another Service on this cluster."
fi

READY=$(kubectl -n "$NS" get deployment "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)

echo "✅ w19 environment ready"
echo "   - namespace: $NS"
echo "   - Deployment: $DEP (nginx:1.25, 2 replicas, ready: ${READY:-?}, no readiness probe)"
echo "   - no Service yet"
echo "   - Task: create NodePort Service $SVC (nodePort 30080, port 80 -> targetPort 80) and add a readiness probe"
