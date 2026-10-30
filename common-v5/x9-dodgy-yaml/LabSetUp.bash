#!/bin/bash
set -e

# x9 - The manifest that does not do what it says
#
# The pre-state is a Service whose targetPort is 8080, and a manifest on disk
# that is wrong in three ways:
#
#   1. the selector says `app: dodgy` while the pod template's labels say
#      `app: dodgy-app` - the API server refuses to create the Deployment
#      at all, and says so in the error;
#   2. the container declares `containerPort: 80` while the Service targets
#      8080 - even once it applies, the Service has no endpoints, and
#      nothing complains;
#   3. there is no `spec.replicas` at all - the API server defaults it to 1,
#      which is almost never what anyone meant.
#
# The manifest is written to disk and NOT applied: the candidate has to find
# the mistakes, fix the file and apply it.

NS=dodgy
SVC=dodgy-svc
LABDIR=/tmp/cka-lab
MANIFEST="$LABDIR/dodgy.yaml"

mkdir -p "$LABDIR"

# Start from a clean pre-state.
kubectl delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: $SVC
  namespace: $NS
spec:
  type: ClusterIP
  selector:
    app: dodgy-app
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
EOF

# The manifest the candidate has to fix. It is deliberately broken in three
# ways, and it is not applied here.
cat > "$MANIFEST" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dodgy-app
  namespace: dodgy
  labels:
    app: dodgy-app
spec:
  selector:
    matchLabels:
      app: dodgy
  template:
    metadata:
      labels:
        app: dodgy-app
    spec:
      containers:
        - name: app
          image: busybox:1.36
          command: ["sh", "-c", "httpd -f -p 8080 -h /tmp"]
          ports:
            - containerPort: 80
              protocol: TCP
EOF

SVC_TPORT=$(kubectl -n "$NS" get svc "$SVC" -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null || true)

echo "✅ x9 environment ready"
echo "   - namespace: $NS"
echo "   - Service: $SVC (ClusterIP, port 80 -> targetPort $SVC_TPORT, selector app=dodgy-app)"
echo "   - the manifest to fix: $MANIFEST"
echo "   - no Deployment yet - the manifest has deliberately not been applied"
echo "   - Task: find the three mistakes in the manifest, fix the file, apply"
echo "     it, and make sure the Service ends up with endpoints"
