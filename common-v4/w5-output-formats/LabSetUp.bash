#!/bin/bash
set -e

# w5 - The same pods, three ways
#
# The pre-state is a Deployment with five healthy replicas and the Service
# in front of it. The question is about OUTPUT: the same five pods, written
# down in two different shapes, one of them sorted by pod IP.

NS=reports
DEP=website
SVC=website
A=/root/q6a.txt
B=/root/q6b.txt

# Start from a clean namespace, so pods from an earlier attempt cannot answer
# the validation on their own.
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
        - name: web
          image: nginx:latest
          ports:
            - containerPort: 80
EOF

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
    app: $DEP
  ports:
    - name: http
      port: 8080
      targetPort: 80
      protocol: TCP
EOF

echo "Waiting for all 5 replicas to be ready..."
kubectl -n "$NS" rollout status deployment/"$DEP" --timeout=300s

# Wait until every pod has an IP. The question sorts by pod IP, and a pod
# without one cannot be ordered.
i=0
while [ "$i" -lt 60 ]; do
  WITHIP=$(kubectl -n "$NS" get pods -l "app=$DEP" \
             -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}' 2>/dev/null \
             | grep -c '[0-9]' || true)
  if [ "${WITHIP:-0}" -ge 5 ]; then
    break
  fi
  sleep 2
  i=$((i+2))
done

# Remove anything a previous attempt left behind, so the question starts clean.
rm -f "$A" "$B"

READY=$(kubectl -n "$NS" get deployment "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
PODS=$(kubectl -n "$NS" get pods -l "app=$DEP" \
         -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | tr '\n' ' ')

echo "✅ w5 environment ready"
echo "   - namespace: $NS"
echo "   - Deployment: $DEP (nginx:latest, 5 replicas, ready: ${READY:-?})"
echo "   - Service: $SVC (ClusterIP, port 8080 -> targetPort 80)"
echo "   - pods: $PODS"
echo "   - Task: write the pods to $A (name and labels, sorted by pod IP) and"
echo "     to $B (name and phase only), both with -o custom-columns"

if [ "${READY:-0}" != "5" ] || [ "${WITHIP:-0}" -lt 5 ] 2>/dev/null; then
  echo "   ⚠️  Not all 5 pods are ready with an IP. Check:" >&2
  echo "      kubectl -n $NS get pods -o wide" >&2
fi
