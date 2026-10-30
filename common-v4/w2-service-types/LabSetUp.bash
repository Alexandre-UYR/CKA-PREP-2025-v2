#!/bin/bash
set -e

# w2 - Three Services, one of them broken
#
# The pre-state is a Deployment that works and a Service that does not: its
# selector asks for app=web-v2 while the pods are labelled app=web, so it has
# no endpoints at all. The candidate has to find that, repair the Service
# where it stands, and then add a NodePort and a LoadBalancer in front of the
# same pods.
#
# The Service's UID is recorded on the namespace so the validator can tell a
# repaired Service from a deleted-and-re-created one.

NS=svcs
DEP=web
SVC=web-clusterip

# Start from a clean namespace, so a previous attempt cannot answer the
# validation on its own.
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
        - name: web
          image: nginx:1.25
          ports:
            - containerPort: 80
EOF

# The broken half: the selector asks for a label no pod carries.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: $SVC
  namespace: $NS
  labels:
    app: $DEP
spec:
  type: ClusterIP
  selector:
    app: $DEP-v2
  ports:
    - name: http
      port: 80
      targetPort: 80
      protocol: TCP
EOF

echo "Waiting for the deployment to be available..."
kubectl -n "$NS" rollout status deployment/"$DEP" --timeout=180s

# Wait until the Service really is broken. A Service whose selector matches
# nothing has no endpoint addresses, and that is the state the task is about.
EP=0
i=0
while [ "$i" -lt 60 ]; do
  EP=$(kubectl -n "$NS" get endpoints "$SVC" \
        -o jsonpath='{range .subsets[*].addresses[*]}{.ip}{"\n"}{end}' 2>/dev/null \
        | grep -c '[0-9]' || true)
  if [ "${EP:-0}" -eq 0 ]; then
    break
  fi
  sleep 2
  i=$((i+2))
done

# Remember which Service the candidate started with. A Service that is fixed
# in place keeps its UID; one that is deleted and re-created does not.
SVCUID=$(kubectl -n "$NS" get svc "$SVC" -o jsonpath='{.metadata.uid}')
kubectl -n "$NS" annotate namespace "$NS" \
  "cka-lab/original-service=$SVCUID" --overwrite >/dev/null

# The task fixes the nodePort at 30080. If the cluster already uses it, the
# candidate cannot create the NodePort Service, so say so now.
INUSE=$(kubectl get svc -A \
          -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name} {range .spec.ports[*]}{.nodePort}{" "}{end}{"\n"}{end}' \
          2>/dev/null | grep -w '30080' || true)

READY=$(kubectl -n "$NS" get deployment "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)

echo "✅ w2 environment ready"
echo "   - namespace: $NS"
echo "   - Deployment: $DEP (nginx:1.25, 2 replicas, ready: ${READY:-?})"
echo "   - Service: $SVC (ClusterIP, port 80 -> targetPort 80, no endpoints)"
echo "   - Task: find out why $SVC has no endpoints and fix it in place, then"
echo "     add web-nodeport (nodePort 30080) and web-lb in front of the same pods"

if [ "${EP:-0}" -ne 0 ]; then
  echo "   ⚠️  The Service still has $EP endpoint addresses. Check:" >&2
  echo "      kubectl -n $NS get endpoints $SVC" >&2
fi
if [ -n "$INUSE" ]; then
  echo "   ⚠️  nodePort 30080 is already taken by: $INUSE" >&2
  echo "      The candidate will not be able to create web-nodeport." >&2
fi
