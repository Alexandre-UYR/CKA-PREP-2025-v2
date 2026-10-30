#!/bin/bash
set -e

# x14 - Make it work harder, then watch it
#
# The pre-state is a small Apache/PHP web app with a CPU request and a CPU
# limit, exposed by a Service, and NO metrics server. The autoscaler has
# nothing to read, so it cannot act.
#
# The candidate has to install a metrics server, write the HorizontalPodAutoscaler
# and put load on the Service. This mirrors the upstream HorizontalPodAutoscaler
# walkthrough: the same image, the same 200m request and 500m limit, the same
# busybox load generator.
#
# The setup removes any metrics-server it finds, so the starting state is the
# same every time. The reset removes it again.

NS=autoscale
DEP=hpa-example
SVC=hpa-example
LABDIR=/tmp/cka-lab

mkdir -p "$LABDIR"

# --- start from a clean namespace -----------------------------------------
kubectl delete namespace "$NS" --ignore-not-found --wait=true --timeout=120s >/dev/null 2>&1 || true

# --- no metrics server ----------------------------------------------------
# The question is about installing one, so the starting state must not have
# one. On a cluster that came with metrics-server (a kind addon, for example)
# this removes it, and the reset removes it again afterwards.
if kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; then
  echo "Removing the metrics-server already present in kube-system, so the pre-state is the same every time."
fi
kubectl delete deployment metrics-server -n kube-system --ignore-not-found >/dev/null 2>&1 || true
kubectl delete serviceaccount metrics-server -n kube-system --ignore-not-found >/dev/null 2>&1 || true
kubectl delete service metrics-server -n kube-system --ignore-not-found >/dev/null 2>&1 || true
kubectl delete clusterrole system:metrics-server --ignore-not-found >/dev/null 2>&1 || true
kubectl delete clusterrole system:aggregated-metrics-reader --ignore-not-found >/dev/null 2>&1 || true
kubectl delete clusterrolebinding system:metrics-server --ignore-not-found >/dev/null 2>&1 || true
kubectl delete clusterrolebinding metrics-server:system:auth-delegator --ignore-not-found >/dev/null 2>&1 || true
kubectl delete rolebinding metrics-server-auth-reader -n kube-system --ignore-not-found >/dev/null 2>&1 || true
kubectl delete apiservice v1beta1.metrics.k8s.io --ignore-not-found >/dev/null 2>&1 || true

# --- the workload and the Service -----------------------------------------
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
        - name: $DEP
          image: registry.k8s.io/hpa-example
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: 200m
            limits:
              cpu: 500m
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
    app: $DEP
EOF

echo "Waiting for the Deployment to become available..."
kubectl -n "$NS" rollout status deployment/"$DEP" --timeout=180s

READY=$(kubectl -n "$NS" get deployment "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)

echo "✅ x14 environment ready"
echo "   - namespace: $NS"
echo "   - Deployment: $DEP (registry.k8s.io/hpa-example, 1 replica, ready: ${READY:-?})"
echo "   - the container requests 200m of CPU and is limited to 500m"
echo "   - Service: $SVC (ClusterIP, port 80 -> targetPort 80)"
echo "   - metrics server: NOT installed"
echo "   - Task: install a metrics server, create the HPA 'hpa' (1-10 pods, 50% of the CPU"
echo "     request), run a load generator Pod against the Service, and watch the Deployment scale up"

if [ "${READY:-0}" != "1" ]; then
  echo "   ⚠️  The Deployment does not report 1 ready replica yet. Check:" >&2
  echo "      kubectl -n $NS get deploy $DEP" >&2
  echo "      kubectl -n $NS describe deploy $DEP" >&2
fi
