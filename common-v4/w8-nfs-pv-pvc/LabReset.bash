#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }
LABDIR=/tmp/cka-lab
NS=web
PV=pvvol
SEED_DIR=/opt/shared

# ---- the claim and the volume ----------------------------------------------
# The claim goes first: a bound PersistentVolume carries a protection
# finalizer, and deleting the claim releases it so the volume can go too.

k -n "$NS" delete pvc --all --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1 || true
k delete pv "$PV" --ignore-not-found --wait=true --timeout=120s >/dev/null 2>&1 || true

# ---- the data on the node ---------------------------------------------------
# A hostPath directory survives everything else: the volume is gone but
# /opt/shared is still on the node, so it is cleaned through a pod that mounts
# the same hostPath - on the same node the setup used.

NODE=""
[ -f "$LABDIR/w8.node" ] && NODE="$(cat "$LABDIR/w8.node" 2>/dev/null)"

# The namespace may have been deleted by the candidate, so it is put back
# before the cleaning pod is created.
k create namespace "$NS" --dry-run=client -o yaml | k apply -f - >/dev/null 2>&1 || true

cat <<EOF | k apply -f - >/dev/null 2>&1 || true
apiVersion: v1
kind: Pod
metadata:
  name: w8-clean
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
        - "rm -rf /shared/* /shared/.[!.]* /shared/..?* 2>/dev/null; ls -A /shared"
      volumeMounts:
        - name: shared
          mountPath: /shared
  volumes:
    - name: shared
      hostPath:
        path: $SEED_DIR
        type: DirectoryOrCreate
EOF

i=0
while [ "$i" -lt 60 ]; do
  PH=$(k -n "$NS" get pod w8-clean -o jsonpath='{.status.phase}' 2>/dev/null || true)
  case "$PH" in Succeeded|Failed) break;; esac
  sleep 2
  i=$((i+2))
done
k -n "$NS" delete pod w8-clean --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1 || true

# ---- the namespace ----------------------------------------------------------

k delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# ---- the setup's own files --------------------------------------------------

rm -f "$LABDIR/w8.node" "$LABDIR/w8.pv.uid" "$LABDIR/w8.seed.txt"

echo "w8 reset: namespace $NS, claim and volume $PV removed"
echo "w8 reset: $SEED_DIR cleaned through a pod on node ${NODE:-<any>}"
