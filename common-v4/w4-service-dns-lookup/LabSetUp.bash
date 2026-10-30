#!/bin/bash
set -e

# w4 - The name that does not resolve
#
# The pre-state is a redis Pod with the right label, a Service that points at
# a label no pod carries, and a busybox pod to run nslookup from. The
# candidate has to repair the Service and then write down both addresses.

NS=dns-demo
REDPOD=redis
SVC=redis-svc
LOOKER=looker
ANSWER=/root/q5.txt

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

# The workload the Service is supposed to be pointing at.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $REDPOD
  namespace: $NS
  labels:
    app: redis
spec:
  containers:
    - name: redis
      image: redis:7
      ports:
        - containerPort: 11211
EOF

# The broken half: the selector asks for a label the pod does not carry.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: $SVC
  namespace: $NS
  labels:
    app: redis
spec:
  type: ClusterIP
  selector:
    app: redis-v2
  ports:
    - name: redis
      port: 11211
      targetPort: 11211
      protocol: TCP
EOF

# Somewhere to run nslookup from. busybox ships the nslookup applet.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $LOOKER
  namespace: $NS
  labels:
    app: looker
spec:
  containers:
    - name: $LOOKER
      image: busybox:1.28
      command: ["sleep", "10000"]
EOF

echo "Waiting for the pods to be Running..."
i=0
while [ "$i" -lt 90 ]; do
  R=$(kubectl -n "$NS" get pod "$REDPOD" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  L=$(kubectl -n "$NS" get pod "$LOOKER" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  if [ "$R" = "Running" ] && [ "$L" = "Running" ]; then
    break
  fi
  sleep 2
  i=$((i+2))
done

# Wait until the Service really is broken: a selector that matches nothing
# means no endpoint addresses.
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

# Clear any answer file from a previous attempt.
rm -f "$ANSWER"

REDIP=$(kubectl -n "$NS" get pod "$REDPOD" -o jsonpath='{.status.podIP}' 2>/dev/null || true)
CIP=$(kubectl -n "$NS" get svc "$SVC" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)

echo "✅ w4 environment ready"
echo "   - namespace: $NS"
echo "   - Pod: $REDPOD (redis:7)"
echo "   - Service: $SVC (ClusterIP, port 11211 -> targetPort 11211, no endpoints)"
echo "   - Pod: $LOOKER (busybox:1.28) - run nslookup from here"
echo "   - Task: find out why $SVC has nothing behind it and fix it, then write"
echo "     the Service address and the $REDPOD Pod address to $ANSWER, one per line"

if [ "${EP:-0}" -ne 0 ]; then
  echo "   ⚠️  The Service still has $EP endpoint addresses. Check:" >&2
  echo "      kubectl -n $NS get endpoints $SVC" >&2
fi
if [ -z "${REDIP:-}" ] || [ -z "${CIP:-}" ]; then
  echo "   ⚠️  The Pod or the Service has no address yet. Check:" >&2
  echo "      kubectl -n $NS get pods -o wide" >&2
  echo "      kubectl -n $NS get svc $SVC" >&2
fi
