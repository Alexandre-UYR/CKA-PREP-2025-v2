#!/bin/bash
set -e

# x13 - Which machine is the busiest
#
# The pre-state is a cluster with no metrics at all, and a namespace with one
# greedy Pod and two quiet ones. The candidate has to install the thing that
# makes `kubectl top` work, and then use it.
#
# Any metrics server that is already installed is removed first, so that the
# starting state really does have no metrics and the exercise is the same on
# every run.

NS=metrics
LABDIR=/tmp/cka-lab

mkdir -p "$LABDIR"

# ---------------------------------------------------------------------------
# No metrics in the starting state
# ---------------------------------------------------------------------------
kubectl -n kube-system delete deployment metrics-server --ignore-not-found --timeout=60s >/dev/null 2>&1 || true
kubectl -n kube-system delete serviceaccount metrics-server --ignore-not-found >/dev/null 2>&1 || true
kubectl delete apiservice v1beta1.metrics.k8s.io --ignore-not-found >/dev/null 2>&1 || true

kubectl delete namespace "$NS" --ignore-not-found --timeout=180s >/dev/null 2>&1 || true
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

# ---------------------------------------------------------------------------
# The three workloads
# ---------------------------------------------------------------------------
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hog
  namespace: $NS
  labels:
    app: hog
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hog
  template:
    metadata:
      labels:
        app: hog
    spec:
      containers:
        - name: hog
          image: busybox:1.36
          command:
            - sh
            - -c
            - |
              while true; do
                a=\$(dd if=/dev/zero bs=1024 count=65536 2>/dev/null | tr '\000' 'x')
                sleep 2
              done
EOF

for n in calm-one calm-two; do
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $n
  namespace: $NS
  labels:
    app: $n
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $n
  template:
    metadata:
      labels:
        app: $n
    spec:
      containers:
        - name: $n
          image: busybox:1.36
          command: ["sh", "-c", "sleep 3600"]
EOF
done

echo "Waiting for the three Pods to be ready..."
i=0
while [ "$i" -lt 120 ]; do
  R=$(kubectl -n "$NS" get pods -o jsonpath='{range .items[*]}{.status.containerStatuses[0].ready}{"\n"}{end}' 2>/dev/null | grep -c '^true$' || true)
  [ "$R" -ge 3 ] && break
  sleep 2
  i=$((i+2))
done

echo "x13 environment ready"
echo "   - namespace: $NS"
echo "   - Deployments: hog (busybox, greedy with memory), calm-one and"
echo "     calm-two (busybox, asleep)"
echo "   - no metrics server is installed, so 'kubectl top' does not work yet"
echo "   - Task: install a metrics server, then write the busiest node to"
echo "     /root/busiest-node.txt and the hungriest pod to /root/hottest-pod.txt"

if ! kubectl top nodes >/dev/null 2>&1; then
  echo "   NOTE: 'kubectl top nodes' does not work yet, as intended. Check with:" >&2
  echo "         kubectl top nodes" >&2
fi
