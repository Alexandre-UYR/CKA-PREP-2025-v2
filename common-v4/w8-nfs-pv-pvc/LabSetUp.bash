#!/bin/bash
set -e

# w8 - A volume with something already on it
#
# The shape of an NFS-backed PV lab, done with a hostPath so that no NFS
# server is needed:
#
#   the PV pvvol    1Gi, ReadWriteMany, Retain, storageClassName "", hostPath
#                   /opt/shared, pinned to one node with a node affinity
#   the data        /opt/shared/index.html, written by a short-lived pod that
#                   mounts the same hostPath - a hostPath resolves on the
#                   NODE, so the directory has to be created there
#   the claim       does not exist yet
#
# The node affinity on the PV is not decoration. A hostPath is node-local: the
# data exists on one node only, and the scheduler has to put the pod that
# uses the claim on that same node. The affinity is what makes that happen
# without telling the candidate anything about it.
#
# Everything is recreated on every run, so the starting state is the same
# every time and the UID recorded here is the UID the candidate has to keep.

NS=web
PV=pvvol
PVC=pvc001
DEP=web
SVC=web
LABDIR=/tmp/cka-lab
SEED_DIR=/opt/shared
SEED_FILE=index.html
SEED_CONTENT='shared content served from the volume'
SEED_POD=seed-content

mkdir -p "$LABDIR"

ensure_ns(){
  local ns=$1 phase i
  if kubectl get ns "$ns" >/dev/null 2>&1; then
    phase=$(kubectl get ns "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [ "$phase" = "Terminating" ]; then
      i=0
      while [ "$i" -lt 60 ]; do
        kubectl get ns "$ns" >/dev/null 2>&1 || break
        sleep 2
        i=$((i+2))
      done
    fi
  fi
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
}

node_taints(){
  kubectl get node "$1" -o jsonpath='{range .spec.taints[*]}{.effect}{"\n"}{end}' 2>/dev/null || true
}

# ---- clean out anything a previous attempt left behind ---------------------
# The claim goes first: a bound PersistentVolume carries a protection
# finalizer, and the volume cannot go until the claim that references it is
# gone.

kubectl -n "$NS" delete pvc --all --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1 || true
kubectl delete pv "$PV" --ignore-not-found --wait=true --timeout=120s >/dev/null 2>&1 || true
kubectl -n "$NS" delete deployment "$DEP" --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1 || true
kubectl -n "$NS" delete service "$SVC" --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1 || true
kubectl -n "$NS" delete pod "$SEED_POD" --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1 || true

ensure_ns "$NS"

# ---- pick the node ---------------------------------------------------------
# The node has to be Ready, and a pod has to be able to run on it - a
# NoSchedule taint would keep the seeding pod and the web pods off it.

NODES=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
if [ -z "$NODES" ]; then
  echo "w8 setup: the cluster reports no nodes - there is nothing to build the pre-state on." >&2
  exit 1
fi

NODE=""
FALLBACK=""
for n in $NODES; do
  ready=$(kubectl get node "$n" -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status}{end}' 2>/dev/null || true)
  [ "$ready" = "True" ] || continue
  if [ -z "$FALLBACK" ]; then FALLBACK="$n"; fi
  if ! node_taints "$n" | grep -qx 'NoSchedule'; then
    NODE="$n"; break
  fi
done
if [ -z "$NODE" ]; then NODE="$FALLBACK"; fi
if [ -z "$NODE" ]; then NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true); fi
printf '%s\n' "$NODE" > "$LABDIR/w8.node"

if [ -z "$NODE" ]; then
  echo "w8 setup: no usable node - there is nothing to build the pre-state on." >&2
  exit 1
fi

# ---- the PersistentVolume --------------------------------------------------
# storageClassName is deliberately the empty string: the claim has to name
# the same empty string, or the API server defaults the claim to the
# cluster's default class and the two never match.

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $PV
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  hostPath:
    path: $SEED_DIR
    type: DirectoryOrCreate
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
                - "$NODE"
EOF

echo "Waiting for the PersistentVolume to become Available..."
i=0
while [ "$i" -lt 60 ]; do
  PH=$(kubectl get pv "$PV" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  [ "$PH" = "Available" ] && break
  sleep 1
  i=$((i+1))
done

# ---- the data on the volume ------------------------------------------------
# A hostPath resolves on the NODE, so the file is written by a pod that mounts
# that hostPath, not by anything running on the machine that holds kubectl.

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $SEED_POD
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
        - |
          printf '%s\n' '$SEED_CONTENT' > /shared/$SEED_FILE
          cat /shared/$SEED_FILE
      volumeMounts:
        - name: shared
          mountPath: /shared
  volumes:
    - name: shared
      hostPath:
        path: $SEED_DIR
        type: DirectoryOrCreate
EOF

SEED_PHASE=""
i=0
while [ "$i" -lt 90 ]; do
  SEED_PHASE=$(kubectl -n "$NS" get pod "$SEED_POD" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  case "$SEED_PHASE" in Succeeded|Failed) break;; esac
  sleep 2
  i=$((i+2))
done

# Read back what was actually written. The validator compares the served body
# against this, not against a guess.
SEED_ACTUAL=$(kubectl -n "$NS" logs "$SEED_POD" 2>/dev/null | tr -d '\r' | sed -e 's/[[:space:]]*$//' || true)
printf '%s\n' "$SEED_ACTUAL" > "$LABDIR/w8.seed.txt"

kubectl -n "$NS" delete pod "$SEED_POD" --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1 || true

# ---- record the state the validator needs -----------------------------------

PV_UID=$(kubectl get pv "$PV" -o jsonpath='{.metadata.uid}' 2>/dev/null || true)
printf '%s\n' "$PV_UID" > "$LABDIR/w8.pv.uid"

PV_PHASE=$(kubectl get pv "$PV" -o jsonpath='{.status.phase}' 2>/dev/null || true)
PV_CLASS=$(kubectl get pv "$PV" -o jsonpath='{.spec.storageClassName}' 2>/dev/null || true)
PV_CAP=$(kubectl get pv "$PV" -o jsonpath='{.spec.capacity.storage}' 2>/dev/null || true)
PV_MODES=$(kubectl get pv "$PV" -o jsonpath='{.spec.accessModes[*]}' 2>/dev/null || true)

echo "✅ w8 environment ready"
echo "   - namespace: $NS"
echo "   - PersistentVolume: $PV ($PV_CAP, $PV_MODES, storageClassName '${PV_CLASS:-}', reclaimPolicy Retain, hostPath $SEED_DIR)"
echo "   - PV phase: ${PV_PHASE:-<unknown>}   PV UID: ${PV_UID:-<unknown>}"
echo "   - the volume is pinned to node $NODE"
echo "   - data on the volume: $SEED_DIR/$SEED_FILE holds '${SEED_ACTUAL:-<nothing>}'"
echo "   - no PersistentVolumeClaim exists yet"
echo "   - Task: bind a claim to the volume, serve what is already on it"

if [ "$SEED_PHASE" != "Succeeded" ]; then
  echo "   ⚠️  The seeding pod did not succeed (phase '$SEED_PHASE') - the volume may not hold its data." >&2
  echo "      Check: kubectl -n $NS get pods" >&2
fi
if [ "$PV_PHASE" != "Available" ]; then
  echo "   ⚠️  The PV is '$PV_PHASE' rather than Available." >&2
  echo "      Check: kubectl describe pv $PV" >&2
fi
if [ -z "$SEED_ACTUAL" ]; then
  echo "   ⚠️  Nothing was read back from $SEED_DIR/$SEED_FILE - the live check has nothing to compare against." >&2
fi
