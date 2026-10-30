#!/bin/bash
set -e

# x20 - An object that was never applied
#
# The pre-state is a Service that was CREATED with `kubectl create`, so it
# carries no kubectl.kubernetes.io/last-applied-configuration annotation.
# `kubectl apply` is a three-way merge: it compares what you are applying with
# what it last applied and with what is live. With no annotation there is no
# "what it last applied", and on a Service the ports list is merged by the
# port NUMBER - so an apply that only mentions port 8080 leaves the old
# port 80 entry behind and the Service ends up exposing both.
#
# The fix is to give kubectl a baseline before applying.

NS=traps
SVC=svc
DEP=web
LABDIR=/tmp/cka-lab

mkdir -p "$LABDIR"

# Start from a clean namespace every time.
kubectl delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
for i in $(seq 1 30); do
  kubectl get namespace "$NS" >/dev/null 2>&1 || break
  sleep 2
done

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

# The Service, made with `kubectl create`. That is the whole point of the
# question: `create` records nothing about how the object was made, so the
# last-applied-configuration annotation is never written.
kubectl -n "$NS" create service clusterip "$SVC" --tcp=80:80

# `kubectl create service` leaves the selector empty, so point it at the
# Deployment's pods. A patch changes one field and leaves everything else
# alone - and it does not add an annotation either.
kubectl -n "$NS" patch svc "$SVC" --type=merge \
  -p '{"spec":{"selector":{"app":"web"}}}'

# The workload the Service selects.
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEP
  namespace: $NS
  labels:
    app: web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: nginx
          image: nginx:1.25
          ports:
            - name: http
              containerPort: 80
EOF

echo "Waiting for the deployment to be available..."
kubectl -n "$NS" rollout status deployment/"$DEP" --timeout=180s

# Remember the Deployment's UID: it is not part of the question and must not
# change.
kubectl -n "$NS" get deploy "$DEP" -o jsonpath='{.metadata.uid}' > "$LABDIR/x20.dep.uid" 2>/dev/null || true

# The provenance of the Service is the point of the question, so check it.
ANN=$(kubectl -n "$NS" get svc "$SVC" \
        -o go-template='{{index .metadata.annotations "kubectl.kubernetes.io/last-applied-configuration"}}' 2>/dev/null || true)
if [ -n "$ANN" ]; then
  echo "WARNING: the Service already carries a last-applied-configuration annotation." >&2
  echo "         The question is about a Service that was CREATED, not APPLIED." >&2
fi

echo "✅ x20 environment ready"
echo "   - namespace: $NS"
echo "   - Service: $SVC (created with kubectl create, port 80 -> targetPort 80,"
echo "     selector app=web, last-applied-configuration: ${ANN:-<none>})"
echo "   - Deployment: $DEP (nginx:1.25, 1 replica, labels app=web) - not part of"
echo "     the question, leave it alone"
echo "   - Task: change the Service to port 8080 -> targetPort 80 with kubectl"
echo "     apply, and save the manifest to /root/svc.yaml"
