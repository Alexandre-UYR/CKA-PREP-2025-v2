#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

NS=volumes
HOSTDIR=/tmp/hostdata

# The namespace takes the Pod, the ConfigMap and the Secret with it. Make sure
# it exists first, so the cleanup pods below have somewhere to live.
k create namespace "$NS" --dry-run=client -o yaml | k apply -f - >/dev/null 2>&1 || true

# The hostPath directory lives on the node's filesystem and survives
# everything: deleting the namespace, deleting the Pod, even deleting the
# cluster's reference to it. Clean it through a Pod that mounts the node's
# /tmp and removes the directory from there - `rm` on the machine running
# kubectl would delete a directory on that machine, not on the node.
for NODE in $(k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
  k -n "$NS" delete pod c12-hostdata-clean --ignore-not-found --wait=true >/dev/null 2>&1 || true

  cat <<EOF | k apply -f - >/dev/null 2>&1 || true
apiVersion: v1
kind: Pod
metadata:
  name: c12-hostdata-clean
  namespace: $NS
spec:
  nodeName: $NODE
  restartPolicy: Never
  containers:
    - name: clean
      image: busybox:1.36
      command: ["sh", "-c", "rm -rf /nodetmp/hostdata && echo cleaned"]
      volumeMounts:
        - name: nodetmp
          mountPath: /nodetmp
  volumes:
    - name: nodetmp
      hostPath:
        path: /tmp
        type: Directory
EOF

  i=0
  while [ $i -lt 30 ]; do
    PHASE=$(k -n "$NS" get pod c12-hostdata-clean -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [ "$PHASE" = "Succeeded" ] || [ "$PHASE" = "Failed" ]; then break; fi
    i=$((i+1)); sleep 2
  done

  k -n "$NS" delete pod c12-hostdata-clean --ignore-not-found --wait=true >/dev/null 2>&1 || true
done

k delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

echo "c12 reset: namespace $NS removed (ConfigMap app-config and Secret app-secret went with it)"
echo "          and $HOSTDIR removed from every node"
