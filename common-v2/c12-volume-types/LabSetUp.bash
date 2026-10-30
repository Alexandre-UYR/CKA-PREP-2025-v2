#!/bin/bash
set -e

# Pre-state for c12: the namespace, the ConfigMap and the Secret the Pod
# mounts, and the hostPath directory on the node.
#
# The hostPath directory is the awkward one. A hostPath volume is resolved by
# the kubelet on the node the Pod lands on - it is the node's own filesystem,
# not the machine running kubectl. So `mkdir` on your laptop does nothing for
# it. The only way to create it from here is a short-lived Pod that mounts the
# same hostPath; the kubelet then creates the directory on the node.
NS=volumes
HOSTDIR=/tmp/hostdata

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: volumes
data:
  nginx.conf: |
    server {
      listen 80;
      server_name _;

      location / {
        root /usr/share/nginx/html;
      }
    }
---
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
  namespace: volumes
type: Opaque
stringData:
  api-key: cka-lab-secret-value
EOF

# Create the host directory on every node, so the Pod works wherever the
# scheduler puts it. The Pod is pinned to one node with nodeName, mounts the
# same hostPath the candidate's Pod will use, and writes a marker file into
# it. DirectoryOrCreate makes the kubelet create the directory on that node.
for NODE in $(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'); do
  kubectl -n "$NS" delete pod c12-hostdata-init --ignore-not-found --wait=true >/dev/null 2>&1 || true

  cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: c12-hostdata-init
  namespace: $NS
spec:
  nodeName: $NODE
  restartPolicy: Never
  containers:
    - name: init
      image: busybox:1.36
      command: ["sh", "-c", "mkdir -p /host && echo 'cka-lab c12 hostdata' > /host/.cka-lab-marker && chmod 0755 /host"]
      volumeMounts:
        - name: host
          mountPath: /host
  volumes:
    - name: host
      hostPath:
        path: $HOSTDIR
        type: DirectoryOrCreate
EOF

  i=0
  PHASE=""
  while [ $i -lt 60 ]; do
    PHASE=$(kubectl -n "$NS" get pod c12-hostdata-init -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [ "$PHASE" = "Succeeded" ] || [ "$PHASE" = "Failed" ]; then break; fi
    i=$((i+1)); sleep 2
  done
  if [ "$PHASE" != "Succeeded" ]; then
    echo "WARNING: could not initialise $HOSTDIR on node $NODE (phase '${PHASE:-unknown}')" >&2
  fi

  kubectl -n "$NS" delete pod c12-hostdata-init --ignore-not-found --wait=true >/dev/null 2>&1 || true
done

echo "✅ c12 environment ready"
echo "   - namespace: $NS"
echo "   - ConfigMap: app-config (key: nginx.conf)"
echo "   - Secret: app-secret (key: api-key)"
echo "   - hostPath directory $HOSTDIR created on:"
kubectl get nodes -o wide --no-headers | awk '{print "       - " $1}'
echo "   - Task: create Pod 'all-volumes' with an emptyDir, a ConfigMap volume,"
echo "     a Secret volume and a hostPath volume, one mount each"
