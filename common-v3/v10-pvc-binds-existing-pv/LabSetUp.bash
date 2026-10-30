#!/bin/bash
set -e

# v10 - The claim that will not bind
#
# The pre-state is a PersistentVolume that is Available and holds data, and a
# PersistentVolumeClaim that asks for exactly what the PV offers - except that
# the claim names no StorageClass, so the API server defaults it to the
# cluster's default class, which is not the class the PV carries. The two
# never match and the claim sits Pending with "no matching persistent volumes
# found".
#
# The StorageClass is the piece people miss: access modes and size can all
# agree and the claim still will not bind.
#
# The namespace, the PV and the claim are recreated on every run, so the setup
# is idempotent and the starting state is always the same.

NS=bind
PV=data-pv
PVC=data
PV_SIZE=500Mi
PV_CLASS=fast
OUR_CLASS=cka-static
LABDIR="/tmp/cka-lab"
DATA_DIR=/tmp/data

mkdir -p "$LABDIR"

# ---- helpers ----------------------------------------------------------------

# The classes the cluster currently marks as default. The annotation map is
# dumped whole and matched, because the annotation key contains dots and
# escaping it in a jsonpath is easy to get wrong.
default_classes(){
  kubectl get storageclass \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
  | while IFS= read -r sc; do
      [ -n "$sc" ] || continue
      ann=$(kubectl get storageclass "$sc" -o jsonpath='{.metadata.annotations}' 2>/dev/null || true)
      case "$ann" in
        *is-default-class*true*) printf '%s\n' "$sc";;
      esac
    done
}

record_created(){
  local name=$1 cur
  cur="$(cat "$LABDIR/v10.sc.created" 2>/dev/null || true)"
  case " $cur " in
    *" $name "*) return 0;;
  esac
  printf '%s%s\n' "${cur:+$cur }$name" > "$LABDIR/v10.sc.created"
}

# ---- the namespace ----------------------------------------------------------

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

# ---- the StorageClasses -----------------------------------------------------
# Two things have to be true for the pre-state to hold:
#
#   1. a class named `fast` exists, so the PV's storageClassName names
#      something real, and so a claim written with `fast` cannot be
#      dynamically provisioned;
#   2. the cluster's default class is NOT `fast` and has no provisioner, so
#      the claim - which names no class - is defaulted to it and simply waits.
#
# The default class is left alone when it is already safe. When it is not, the
# setup puts its own no-provisioner class in place and records what to restore.

if kubectl get storageclass "$PV_CLASS" >/dev/null 2>&1; then
  echo "StorageClass $PV_CLASS already exists - leaving it alone."
else
  kubectl create storageclass "$PV_CLASS" \
    --provisioner=kubernetes.io/no-provisioner --reclaim-policy=Retain
  record_created "$PV_CLASS"
fi

DEF_LIST=$(default_classes)
DEF_COUNT=$(printf '%s\n' "$DEF_LIST" | grep -c . | tr -d ' ')
DEF_NAME=$(printf '%s\n' "$DEF_LIST" | head -n 1)
DEF_PROV=""
if [ -n "$DEF_NAME" ]; then
  DEF_PROV=$(kubectl get storageclass "$DEF_NAME" -o jsonpath='{.provisioner}' 2>/dev/null || true)
fi

NEED_NEW=0
if [ "$DEF_COUNT" -eq 0 ]; then NEED_NEW=1; fi
if [ "$DEF_COUNT" -gt 1 ]; then NEED_NEW=1; fi
if [ -n "$DEF_NAME" ] && [ "$DEF_NAME" = "$PV_CLASS" ]; then NEED_NEW=1; fi
if [ -n "$DEF_PROV" ] && [ "$DEF_PROV" != "kubernetes.io/no-provisioner" ]; then NEED_NEW=1; fi

if [ "$NEED_NEW" -eq 1 ]; then
  echo "The cluster's default StorageClass is not usable for a static PV - putting $OUR_CLASS in place."
  # Record the previous default(s) so the reset can put them back.
  if [ -z "$DEF_LIST" ]; then
    printf '%s\n' "none" > "$LABDIR/v10.sc.restore"
  else
    printf '%s\n' "$(printf '%s' "$DEF_LIST" | tr '\n' ' ')" > "$LABDIR/v10.sc.restore"
  fi
  # Exactly one default may exist at any time: the API server refuses to
  # default a claim when it can see two.
  for sc in $DEF_LIST; do
    kubectl annotate storageclass "$sc" storageclass.kubernetes.io/is-default-class- --overwrite >/dev/null 2>&1 || true
  done
  if ! kubectl get storageclass "$OUR_CLASS" >/dev/null 2>&1; then
    kubectl create storageclass "$OUR_CLASS" \
      --provisioner=kubernetes.io/no-provisioner --reclaim-policy=Retain
    record_created "$OUR_CLASS"
  fi
  kubectl annotate storageclass "$OUR_CLASS" storageclass.kubernetes.io/is-default-class=true --overwrite
  EFFECTIVE_DEFAULT="$OUR_CLASS"
else
  EFFECTIVE_DEFAULT="$DEF_NAME"
fi

printf '%s\n' "$EFFECTIVE_DEFAULT" > "$LABDIR/v10.sc.before"

# ---- a node for the hostPath ------------------------------------------------
# The hostPath directory lives on one node, so the pod that writes the data and
# the pod that cleans it up are pinned to the same one.

NODE=""
for n in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  ready=$(kubectl get node "$n" -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status}{end}' 2>/dev/null || true)
  [ "$ready" = "True" ] || continue
  cp=$(kubectl get node "$n" -o jsonpath='{.metadata.labels}' 2>/dev/null || true)
  if ! printf '%s' "$cp" | grep -Eq 'node-role\.kubernetes\.io/(control-plane|master)'; then
    NODE="$n"; break
  fi
  [ -z "$NODE" ] && NODE="$n"
done
[ -z "$NODE" ] && NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
printf '%s\n' "$NODE" > "$LABDIR/v10.node"

# ---- the PersistentVolume ---------------------------------------------------
# A previous attempt may have bound the pair. Start again from an Available PV
# and an unbound claim, so the pre-state is the same every time.

kubectl -n "$NS" delete pvc "$PVC" --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1 || true
kubectl delete pv "$PV" --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1 || true
i=0
while [ "$i" -lt 30 ]; do
  kubectl get pv "$PV" >/dev/null 2>&1 || break
  sleep 1
  i=$((i+1))
done

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $PV
spec:
  capacity:
    storage: $PV_SIZE
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: $PV_CLASS
  hostPath:
    path: $DATA_DIR
    type: DirectoryOrCreate
EOF

echo "Waiting for the PersistentVolume to become Available..."
i=0
while [ "$i" -lt 30 ]; do
  PH=$(kubectl get pv "$PV" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  [ "$PH" = "Available" ] && break
  sleep 1
  i=$((i+1))
done

# ---- the data on the volume -------------------------------------------------
# The volume holds data, and the data has to survive the whole exercise: the
# candidate is told not to delete the PV.

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: seed-data
  namespace: $NS
spec:
  restartPolicy: Never
  nodeName: $NODE
  containers:
    - name: seed
      image: busybox:1.36
      command:
        - sh
        - -c
        - "echo 'data that must survive' > /data/data.txt && ls -l /data"
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      hostPath:
        path: $DATA_DIR
        type: DirectoryOrCreate
EOF

SEED_PHASE=""
i=0
while [ "$i" -lt 60 ]; do
  SEED_PHASE=$(kubectl -n "$NS" get pod seed-data -o jsonpath='{.status.phase}' 2>/dev/null || true)
  [ "$SEED_PHASE" = "Succeeded" ] && break
  [ "$SEED_PHASE" = "Failed" ] && break
  sleep 2
  i=$((i+2))
done
kubectl -n "$NS" delete pod seed-data --ignore-not-found --wait=true >/dev/null 2>&1 || true

# ---- the PersistentVolumeClaim ----------------------------------------------
# No storageClassName: the API server defaults it to the cluster's default
# class, which is not the class the PV carries.

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC
  namespace: $NS
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: $PV_SIZE
EOF

echo "Waiting for the claim to settle into Pending (it must not be provisioned dynamically)..."
i=0
while [ "$i" -lt 40 ]; do
  PH=$(kubectl -n "$NS" get pvc "$PVC" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  VN=$(kubectl -n "$NS" get pvc "$PVC" -o jsonpath='{.spec.volumeName}' 2>/dev/null || true)
  if [ "$PH" = "Pending" ] && [ -z "$VN" ]; then
    # Give a dynamic provisioner a chance to bind it to the wrong volume.
    sleep 5
    PH2=$(kubectl -n "$NS" get pvc "$PVC" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    [ "$PH2" = "Pending" ] && break
  fi
  sleep 2
  i=$((i+2))
done

CLAIM_PHASE=$(kubectl -n "$NS" get pvc "$PVC" -o jsonpath='{.status.phase}' 2>/dev/null || true)
CLAIM_CLASS=$(kubectl -n "$NS" get pvc "$PVC" -o jsonpath='{.spec.storageClassName}' 2>/dev/null || true)
PV_PHASE=$(kubectl get pv "$PV" -o jsonpath='{.status.phase}' 2>/dev/null || true)

# ---- record the state the validator needs -----------------------------------

PV_UID=$(kubectl get pv "$PV" -o jsonpath='{.metadata.uid}' 2>/dev/null || true)
printf '%s\n' "$PV_UID" > "$LABDIR/v10.pv.uid"

echo "✅ v10 environment ready"
echo "   - namespace: $NS"
echo "   - PersistentVolume: $PV ($PV_SIZE, ReadWriteOnce, storageClassName $PV_CLASS, reclaimPolicy Retain, hostPath $DATA_DIR)"
echo "   - PV phase: ${PV_PHASE:-<unknown>}   PV UID: ${PV_UID:-<unknown>}"
echo "   - PersistentVolumeClaim: $PVC ($PV_SIZE, ReadWriteOnce, no storageClassName of its own)"
echo "   - claim phase: ${CLAIM_PHASE:-<unknown>}   claim storageClassName: ${CLAIM_CLASS:-<none>}"
echo "   - cluster default StorageClass: ${EFFECTIVE_DEFAULT:-<none>} (recorded in $LABDIR/v10.sc.before)"
if [ "$EFFECTIVE_DEFAULT" = "$OUR_CLASS" ]; then
  echo "   - NOTE: the cluster's default StorageClass was swapped for this exercise, because the"
  echo "     original one has a provisioner and would have dynamically provisioned the claim"
  echo "     instead of leaving it Pending. './lab.sh v10 reset' puts the original back."
fi
echo "   - data on the volume: $DATA_DIR/data.txt on node $NODE"
echo "   - Task: find out why the claim will not bind to the PV that is sitting right there, and make it bind"

if [ "$CLAIM_PHASE" != "Pending" ]; then
  echo "   ⚠️  The claim is '$CLAIM_PHASE' rather than Pending - the pre-state is not broken as described." >&2
  echo "      Check: kubectl -n $NS describe pvc $PVC" >&2
fi
if [ "$PV_PHASE" != "Available" ]; then
  echo "   ⚠️  The PV is '$PV_PHASE' rather than Available." >&2
  echo "      Check: kubectl describe pv $PV" >&2
fi
if [ "$SEED_PHASE" != "Succeeded" ]; then
  echo "   ⚠️  The seeding pod did not succeed (phase '$SEED_PHASE') - the volume may not hold its data." >&2
  echo "      Check: kubectl -n $NS get pods" >&2
fi
