#!/bin/bash
set -uo pipefail

NS=mariadb
STATE=/tmp/cka-lab

echo "🔄 Resetting Q1 (MariaDB persistent volume)..."

# The hostPath directory is node-local, so remember which node the database was
# running on before the namespace (and with it the pod) disappears.
NODE="$(kubectl get pods -n "$NS" -l app=mariadb -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)"

# The namespace holds the PVC and the Deployment the candidate created.
kubectl delete namespace "$NS" --ignore-not-found --timeout=120s

# The PV has reclaim policy Retain, so deleting the namespace does NOT delete it.
kubectl delete pv mariadb-pv --ignore-not-found --timeout=60s

# The MariaDB data directory lives on the node's disk and survives everything
# else: clean it through a pod that mounts it, never with rm on your machine.
mkdir -p "$STATE"
cat > "$STATE/q1-clean-pod.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: cka-q1-clean
spec:
  restartPolicy: Never
$( [ -n "$NODE" ] && echo "  nodeName: $NODE" )
  containers:
  - name: clean
    image: busybox:stable
    command: ["sh","-c","rm -rf /mnt/data/mariadb/* /mnt/data/mariadb/.[!.]* 2>/dev/null; exit 0"]
    volumeMounts:
    - name: data
      mountPath: /mnt/data/mariadb
  volumes:
  - name: data
    hostPath:
      path: /mnt/data/mariadb
EOF
kubectl delete pod cka-q1-clean --ignore-not-found >/dev/null 2>&1
kubectl apply -f "$STATE/q1-clean-pod.yaml" >/dev/null 2>&1 || true
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/cka-q1-clean --timeout=60s >/dev/null 2>&1 || true
kubectl delete pod cka-q1-clean --ignore-not-found >/dev/null 2>&1
rm -f "$STATE/q1-clean-pod.yaml"

# The manifest handed to the candidate, and the PV UID captured at setup time.
rm -f ~/mariadb-deploy.yaml
rm -f "$STATE/q1.pv.uid"

echo "✅ Q1 reset: namespace mariadb, PV mariadb-pv, the node data directory and ~/mariadb-deploy.yaml are gone."
