#!/bin/bash
set -e

# x15 - The Service that selects nothing
#
# The pre-state is a Deployment whose pods are labelled app=cart-v2 and a
# Service whose selector says app=cart. The two do not match, so the Service
# has no endpoints - while everything looks healthy, because a Service with a
# selector that matches nothing is a perfectly valid object.
#
# The fix has to be made to the Service, in place: the pods may not be
# relabelled, and the Service may not be deleted and re-created. The grader
# compares the Service's UID with the one recorded here.

NS=shop
DEP=cart
SVC=cart-svc
LABDIR=/tmp/cka-lab

mkdir -p "$LABDIR"

kubectl delete namespace "$NS" --ignore-not-found --wait=true --timeout=120s >/dev/null 2>&1 || true
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
      app: cart-v2
  template:
    metadata:
      labels:
        app: cart-v2
    spec:
      containers:
        - name: $DEP
          image: nginx:1.25
          ports:
            - containerPort: 80
EOF

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: $SVC
  namespace: $NS
spec:
  type: ClusterIP
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
  selector:
    app: cart
EOF

echo "Waiting for the Deployment to become available..."
kubectl -n "$NS" rollout status deployment/"$DEP" --timeout=180s

# Remember the Service's UID: it has to be edited in place, not replaced.
kubectl -n "$NS" get service "$SVC" -o jsonpath='{.metadata.uid}' > "$LABDIR/x15.svc.uid" 2>/dev/null || true

READY=$(kubectl -n "$NS" get deployment "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
EP=$(kubectl -n "$NS" get endpoints "$SVC" -o jsonpath='{range .subsets[*].addresses[*]}{.ip}{"\n"}{end}' 2>/dev/null | grep -c '[0-9]' || true)

echo "✅ x15 environment ready"
echo "   - namespace: $NS"
echo "   - Deployment: $DEP (nginx:1.25, 2 replicas, ready: ${READY:-?}), pods labelled app=cart-v2"
echo "   - Service: $SVC (ClusterIP, port 80 -> targetPort 80), selector app=cart"
echo "   - endpoint addresses on the Service: ${EP:-0}"
echo "   - Task: make the Service select the pods that are there, without re-creating the"
echo "     Service and without relabelling the pods"

if [ "${READY:-0}" != "2" ]; then
  echo "   ⚠️  The Deployment does not report 2 ready replicas yet. Check:" >&2
  echo "      kubectl -n $NS get deploy $DEP" >&2
fi
if [ "${EP:-0}" != "0" ]; then
  echo "   ⚠️  The Service already has endpoints; the pre-state is not what the task describes." >&2
  echo "      kubectl -n $NS get endpoints $SVC" >&2
fi
