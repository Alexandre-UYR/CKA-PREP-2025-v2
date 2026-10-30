#!/bin/bash
set -e

# w18 - The Service's port is not the container's port
#
# The container port already exists and is NAMED. The task is to build a
# Service whose targetPort refers to that name, while the Service's own port
# is a different number - the two are separate fields and both have to be
# right. There is no Service yet: creating it is the whole answer.

NS=web
DEP=site
SVC=site-svc
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
  replicas: 5
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
          image: nginx:latest
          ports:
            - name: http
              containerPort: 80
              protocol: TCP
EOF

echo "Waiting for the deployment to be available..."
kubectl -n "$NS" rollout status deployment/"$DEP" --timeout=180s

# The named container port is the whole point of the question, so make sure it
# really is there before handing over.
PORTNAME=$(kubectl -n "$NS" get deployment "$DEP" -o jsonpath='{.spec.template.spec.containers[0].ports[0].name}' 2>/dev/null || true)
PORTNUM=$(kubectl -n "$NS" get deployment "$DEP" -o jsonpath='{.spec.template.spec.containers[0].ports[0].containerPort}' 2>/dev/null || true)
if [ "$PORTNAME" = "http" ] && [ "$PORTNUM" = "80" ]; then
  echo "The container declares a port named 'http' on port 80."
else
  echo "WARNING: the container port is named '$PORTNAME' on port '${PORTNUM:-?}', expected 'http' on 80."
fi

READY=$(kubectl -n "$NS" get deployment "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)

echo "✅ w18 environment ready"
echo "   - namespace: $NS"
echo "   - Deployment: $DEP (nginx:latest, 5 replicas, ready: ${READY:-?})"
echo "   - container port: name=$PORTNAME port=${PORTNUM:-?}"
echo "   - Task: create Service $SVC with port 8080 named 'http' and targetPort 'http'"
