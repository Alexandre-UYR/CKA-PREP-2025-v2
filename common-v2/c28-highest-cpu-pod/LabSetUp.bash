#!/bin/bash
set -e

# Pre-state for c28: a namespace with three small Deployments, one of which
# burns CPU and two of which do not.
#
# The labels are the point of the question. All three carry `app=<name>`, and
# `cpu-hog` and `calm-one` also carry `workload=batch`, while `calm-two`
# carries `workload=web`. So a candidate who narrows the search with
# `-l workload=batch` gets two pods back and still has to read the CPU column
# to work out which one is actually hot. A candidate who picks a label that
# matches nothing gets an empty list and has to widen the selector.
#
# `kubectl top` needs a metrics server. If there is none, the question cannot
# be measured - the validator skips that comparison and says so.

NS=metrics

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n "$NS" -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cpu-hog
  namespace: metrics
  labels:
    app: cpu-hog
    workload: batch
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cpu-hog
  template:
    metadata:
      labels:
        app: cpu-hog
        workload: batch
    spec:
      containers:
        - name: cpu-hog
          image: busybox:1.36
          command:
            - sh
            - -c
            - "while true; do :; done"
          resources:
            requests:
              cpu: 100m
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: calm-one
  namespace: metrics
  labels:
    app: calm-one
    workload: batch
spec:
  replicas: 1
  selector:
    matchLabels:
      app: calm-one
  template:
    metadata:
      labels:
        app: calm-one
        workload: batch
    spec:
      containers:
        - name: calm-one
          image: busybox:1.36
          command:
            - sh
            - -c
            - "sleep 3600"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: calm-two
  namespace: metrics
  labels:
    app: calm-two
    workload: web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: calm-two
  template:
    metadata:
      labels:
        app: calm-two
        workload: web
    spec:
      containers:
        - name: calm-two
          image: busybox:1.36
          command:
            - sh
            - -c
            - "sleep 3600"
EOF

# Give the workloads a moment to start. The grader reads the live CPU, so the
# busy loop has to be running before the candidate looks.
for d in cpu-hog calm-one calm-two; do
  kubectl rollout status "deployment/$d" -n "$NS" --timeout=120s >/dev/null 2>&1 || true
done
sleep 5

if kubectl top pods -n "$NS" >/dev/null 2>&1; then
  echo "   - metrics are available: 'kubectl top pods -n $NS' works"
else
  echo "   - WARNING: 'kubectl top pods -n $NS' does not work here (no metrics server?)"
  echo "   - WARNING: the question cannot be measured in this cluster; the grader"
  echo "   - WARNING: will skip the comparison against the live reading"
fi

echo "✅ c28 environment ready"
echo "   - namespace: $NS"
echo "   - cpu-hog   (app=cpu-hog,   workload=batch) - burns CPU"
echo "   - calm-one  (app=calm-one,  workload=batch) - sleeps"
echo "   - calm-two  (app=calm-two,  workload=web)   - sleeps"
echo "   - Task: find the Pod using the most CPU and write it to /root/hot-pod.txt"
