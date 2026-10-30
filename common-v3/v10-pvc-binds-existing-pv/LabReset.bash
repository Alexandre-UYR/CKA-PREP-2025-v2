#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }
LABDIR="/tmp/cka-lab"
NS=bind
PV=data-pv
PVC=data
DATA_DIR=/tmp/data

# ---- the claim and the volume ----------------------------------------------
# The claim goes first: a bound PersistentVolume carries a protection
# finalizer, and deleting the claim releases it so the volume can go too.

k -n "$NS" delete pvc "$PVC" --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1 || true
k delete pv "$PV" --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1 || true

# ---- the data on the node ---------------------------------------------------
# A hostPath directory survives everything else: the volume is gone but
# /tmp/data is still on the node, so it is cleaned through a pod that mounts
# the same hostPath - on the same node the setup used.

NODE=""
[ -f "$LABDIR/v10.node" ] && NODE="$(cat "$LABDIR/v10.node" 2>/dev/null)"

if k get namespace "$NS" >/dev/null 2>&1; then
  cat <<EOF | k apply -f - >/dev/null 2>&1 || true
apiVersion: v1
kind: Pod
metadata:
  name: clean-data
  namespace: $NS
spec:
  restartPolicy: Never
  nodeName: $NODE
  containers:
    - name: clean
      image: busybox:1.36
      command:
        - sh
        - -c
        - "rm -rf /data/* /data/.[!.]* /data/..?* 2>/dev/null; ls -A /data"
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      hostPath:
        path: $DATA_DIR
        type: DirectoryOrCreate
EOF
  i=0
  while [ "$i" -lt 60 ]; do
    PH=$(k -n "$NS" get pod clean-data -o jsonpath='{.status.phase}' 2>/dev/null || true)
    case "$PH" in Succeeded|Failed) break;; esac
    sleep 2
    i=$((i+2))
  done
  k -n "$NS" delete pod clean-data --ignore-not-found --wait=true >/dev/null 2>&1 || true
fi

# ---- the namespace ----------------------------------------------------------

k delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# ---- the StorageClasses -----------------------------------------------------
# The classes the setup created go away, and the classes that were default
# before the setup ran are default again.

CREATED=""
[ -f "$LABDIR/v10.sc.created" ] && CREATED="$(cat "$LABDIR/v10.sc.created" 2>/dev/null)"
for sc in $CREATED; do
  k delete storageclass "$sc" --ignore-not-found >/dev/null 2>&1 || true
done

RESTORE=""
[ -f "$LABDIR/v10.sc.restore" ] && RESTORE="$(cat "$LABDIR/v10.sc.restore" 2>/dev/null)"
if [ -n "$RESTORE" ] && [ "$RESTORE" != "none" ]; then
  for sc in $RESTORE; do
    k annotate storageclass "$sc" storageclass.kubernetes.io/is-default-class=true --overwrite >/dev/null 2>&1 || true
  done
fi

# ---- the setup's own files --------------------------------------------------

rm -f "$LABDIR/v10.pv.uid" "$LABDIR/v10.sc.before" "$LABDIR/v10.sc.restore" "$LABDIR/v10.sc.created" "$LABDIR/v10.node"

echo "v10 reset: namespace $NS, claim $PVC and volume $PV removed"
echo "v10 reset: $DATA_DIR cleaned through a pod on node ${NODE:-<any>}"
echo "v10 reset: the StorageClasses the setup created were deleted and the previous default restored"
