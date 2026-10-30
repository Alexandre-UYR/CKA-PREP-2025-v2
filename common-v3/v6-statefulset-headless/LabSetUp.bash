#!/bin/bash
set -e

# v6 - Give each pod its own identity and its own disk
#
# The pre-state is a headless Service and a plain Deployment:
#
#   Service web-headless  clusterIP: None, selector app=web
#                         -> a headless Service, which is the thing that issues
#                            the per-pod DNS names
#   Deployment web         1 replica, labels app=web
#                         -> pods with no stable identity and no storage
#
# Turning that into a StatefulSet is the task. The namespace, the Service and
# the Deployment are recreated on every run, so the setup is idempotent and
# the starting state is always the same.

NS=stateful
SVC=web-headless
DEP=web
IMAGE=nginx:1.25

kubectl delete namespace "$NS" --ignore-not-found --timeout=120s
kubectl create namespace "$NS"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: $SVC
  namespace: $NS
  labels:
    app: $DEP
spec:
  clusterIP: None
  selector:
    app: $DEP
  ports:
    - name: http
      port: 80
      targetPort: 80
---
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
      containers:
        - name: web
          image: $IMAGE
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 80
EOF

# The claim templates have to name a StorageClass that exists, and the default
# one is what the task asks for. Find it here so the setup can say so.
DEFAULT_SC=$(kubectl get storageclass \
  -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -1)

echo "Waiting for the Deployment's pod to come up, so the pre-state is the plain workload it claims to be..."
READY=""
i=0
while [ "$i" -lt 90 ]; do
  READY=$(kubectl -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
  [ "$READY" = "1" ] && break
  sleep 2
  i=$((i+2))
done

echo "✅ v6 environment ready"
echo "   - namespace: $NS"
echo "   - headless Service: $SVC (clusterIP: None, selector app=$DEP, port 80)"
echo "   - Deployment: $DEP (1 replica, image $IMAGE, labels app=$DEP)"
echo "   - default StorageClass: ${DEFAULT_SC:-<none>}"
echo "   - Task: turn the $DEP workload into a StatefulSet with a stable identity and per-pod storage"

if [ -z "$DEFAULT_SC" ]; then
  echo "   ⚠️  This cluster has no default StorageClass. The claims will not bind" >&2
  echo "      until one is marked default." >&2
fi
if [ "$READY" != "1" ]; then
  echo "   ⚠️  The Deployment's pod is not ready yet. Check:" >&2
  echo "      kubectl -n $NS get pods" >&2
fi
