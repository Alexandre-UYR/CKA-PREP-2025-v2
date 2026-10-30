#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

NS=resize
PV=expand-pv
PVC=expand-pvc
SC=expandable

# The hostPath directory lives on the node, not in the cluster, and it
# survives everything else. It has to be cleaned from the node, through a pod
# that mounts the node's /tmp - mounting the parent and removing the
# subdirectory takes the directory itself with it, not just its contents.
for n in $(k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
  k -n "$NS" delete pod c10-cleanup --ignore-not-found --wait=true >/dev/null 2>&1 || true

  cat <<EOF | k apply -f - >/dev/null 2>&1 || true
apiVersion: v1
kind: Pod
metadata:
  name: c10-cleanup
  namespace: $NS
spec:
  nodeName: $n
  restartPolicy: Never
  containers:
    - name: cleanup
      image: busybox:1.36
      command: ["sh", "-c", "rm -rf /host-tmp/expand-data; echo cleaned"]
      volumeMounts:
        - name: hosttmp
          mountPath: /host-tmp
  volumes:
    - name: hosttmp
      hostPath:
        path: /tmp
        type: Directory
EOF

  i=0
  while [ "$i" -lt 20 ]; do
    PH=$(k -n "$NS" get pod c10-cleanup -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$PH" = "Succeeded" ] || [ "$PH" = "Failed" ]; then break; fi
    i=$((i+1)); sleep 2
  done

  k -n "$NS" delete pod c10-cleanup --ignore-not-found --wait=true >/dev/null 2>&1 || true
done

k -n "$NS" delete pvc "$PVC" --ignore-not-found --timeout=60s >/dev/null 2>&1 || true
k delete pv "$PV" --ignore-not-found >/dev/null 2>&1 || true
k delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
k delete sc "$SC" --ignore-not-found >/dev/null 2>&1 || true

echo "c10 reset: namespace resize, the claim, the volume, the expandable StorageClass and /tmp/expand-data are gone"
