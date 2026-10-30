#!/bin/bash
set -e

# v20 - Guaranteed, not Burstable
#
# The pre-state is a Deployment in a namespace that carries a LimitRange with
# both `default` and `defaultRequest`. The main container sets only limits and
# the init container sets nothing at all, so the LimitRanger admission plugin
# fills in the missing requests - with values that are smaller than the limits.
# The pod therefore lands in the Burstable QoS class even though it looks, in
# `kubectl get pod -o yaml`, like it has everything.
#
# The LimitRange has to exist BEFORE the pod is created: the defaults are
# applied by the admission plugin, at pod creation time, not by the Deployment
# controller.
#
# The namespace is recreated on every run, so the setup is idempotent and the
# starting state is always the same.

NS=qos
DEP=mixed
LR=defaults

kubectl delete namespace "$NS" --ignore-not-found --wait=true --timeout=120s >/dev/null 2>&1 || true
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: LimitRange
metadata:
  name: $LR
  namespace: $NS
spec:
  limits:
    - type: Container
      default:
        cpu: 100m
        memory: 128Mi
      defaultRequest:
        cpu: 50m
        memory: 64Mi
EOF

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
      initContainers:
        - name: init
          image: busybox:1.36
          command: ["sh", "-c", "echo init done"]
      containers:
        - name: app
          image: busybox:1.36
          command: ["sh", "-c", "sleep 3600"]
          resources:
            limits:
              cpu: 200m
              memory: 256Mi
EOF

echo "Waiting for the pod to come up and settle into the Burstable QoS class..."
QOS=""
PHASE=""
i=0
while [ "$i" -lt 90 ]; do
  QOS=$(kubectl -n "$NS" get pods -l "app=$DEP" -o jsonpath='{.items[0].status.qosClass}' 2>/dev/null) || QOS=""
  PHASE=$(kubectl -n "$NS" get pods -l "app=$DEP" -o jsonpath='{.items[0].status.phase}' 2>/dev/null) || PHASE=""
  [ "$QOS" = "Burstable" ] && [ "$PHASE" = "Running" ] && break
  sleep 2
  i=$((i+2))
done

APP_RQ_CPU=$(kubectl -n "$NS" get pod -l "app=$DEP" -o jsonpath='{.items[0].spec.containers[0].resources.requests.cpu}' 2>/dev/null) || APP_RQ_CPU=""
APP_RQ_MEM=$(kubectl -n "$NS" get pod -l "app=$DEP" -o jsonpath='{.items[0].spec.containers[0].resources.requests.memory}' 2>/dev/null) || APP_RQ_MEM=""
INIT_RQ_CPU=$(kubectl -n "$NS" get pod -l "app=$DEP" -o jsonpath='{.items[0].spec.initContainers[0].resources.requests.cpu}' 2>/dev/null) || INIT_RQ_CPU=""
INIT_RQ_MEM=$(kubectl -n "$NS" get pod -l "app=$DEP" -o jsonpath='{.items[0].spec.initContainers[0].resources.requests.memory}' 2>/dev/null) || INIT_RQ_MEM=""

echo "✅ v20 environment ready"
echo "   - namespace: $NS"
echo "   - LimitRange: $LR (default cpu=100m memory=128Mi, defaultRequest cpu=50m memory=64Mi)"
echo "   - Deployment: $DEP (1 replica, busybox:1.36, container 'app' + init container 'init')"
echo "   - the 'app' container sets limits only (cpu 200m, memory 256Mi); 'init' sets nothing"
echo "   - the LimitRange filled in the missing requests:"
echo "       app  requests cpu=${APP_RQ_CPU:-<none>} memory=${APP_RQ_MEM:-<none>}"
echo "       init requests cpu=${INIT_RQ_CPU:-<none>} memory=${INIT_RQ_MEM:-<none>}"
echo "   - pod QoS class: ${QOS:-<unknown>}"
echo "   - Task: make every container, the init one included, set its requests"
echo "     equal to its limits, so the pod lands in the Guaranteed class"

if [ "$QOS" != "Burstable" ]; then
  echo "   ⚠️  The pod has not reached the Burstable QoS class yet. Check:" >&2
  echo "      kubectl -n $NS get pod -l app=$DEP -o yaml" >&2
  echo "      kubectl -n $NS describe pod -l app=$DEP" >&2
fi
