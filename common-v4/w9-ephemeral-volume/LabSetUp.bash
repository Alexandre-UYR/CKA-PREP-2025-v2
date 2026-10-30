#!/bin/bash
set -e

# w9 - A volume that belongs to one Pod
#
# The pre-state is a namespace and a cluster that can provision volumes:
#
#   namespace ephem        empty
#   the default class      has to be able to dynamically provision, otherwise
#                          the ephemeral claim stays Pending and the Pod
#                          never starts
#
# The DaemonSet-style pre-state checks do not apply here: nothing is broken.
# What the setup has to guarantee is that the question is COMPLETABLE - a
# generic ephemeral volume is provisioned by the default StorageClass, so the
# default StorageClass has to be one that can provision.
#
# If the cluster's default class carries kubernetes.io/no-provisioner, or if
# there is no default class at all, the setup puts a class that can provision
# in its place and records what to restore. The reset puts the cluster's own
# default back.

NS=ephem
LABDIR=/tmp/cka-lab

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

ensure_ns "$NS"

# ---- the default StorageClass ----------------------------------------------
# A generic ephemeral volume is a claim without a claim of its own: it is
# provisioned by whatever the default StorageClass is. That class has to be
# able to provision.

DEF_LIST=$(default_classes)
DEF_NAME=$(printf '%s\n' "$DEF_LIST" | grep . | head -n 1 || true)
DEF_PROV=""
if [ -n "$DEF_NAME" ]; then
  DEF_PROV=$(kubectl get storageclass "$DEF_NAME" -o jsonpath='{.provisioner}' 2>/dev/null || true)
fi

# Any class whose provisioner is a real one.
CLASSES=$(kubectl get storageclass -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
GOOD=""
for sc in $CLASSES; do
  prov=$(kubectl get storageclass "$sc" -o jsonpath='{.provisioner}' 2>/dev/null || true)
  [ -n "$prov" ] || continue
  if [ "$prov" = "kubernetes.io/no-provisioner" ]; then continue; fi
  GOOD="$sc"
  break
done

# A usable default, if the cluster already has one.
if [ -n "$DEF_NAME" ] && [ "$DEF_PROV" != "kubernetes.io/no-provisioner" ] && [ -n "$DEF_PROV" ]; then
  GOOD="$DEF_NAME"
fi

CHANGED="no"
DEF_COUNT=$(printf '%s\n' "$DEF_LIST" | grep -c . || true)
DEF_COUNT=${DEF_COUNT:-0}

if [ -z "$GOOD" ]; then
  echo "w9 setup: no StorageClass in this cluster can dynamically provision a volume." >&2
  echo "          The ephemeral claim will stay Pending and the Pod will not start." >&2
else
  NEED_FIX="no"
  if [ "$GOOD" != "$DEF_NAME" ]; then NEED_FIX="yes"; fi
  if [ "$DEF_COUNT" -gt 1 ] 2>/dev/null; then NEED_FIX="yes"; fi

  if [ "$NEED_FIX" = "yes" ]; then
    if [ "$GOOD" != "$DEF_NAME" ]; then
      echo "The cluster's default StorageClass is '${DEF_NAME:-<none>}' (provisioner '${DEF_PROV:-<none>}', which cannot provision) - putting $GOOD in its place."
    else
      echo "$DEF_COUNT StorageClasses are marked as the default - the API server refuses to default a claim when it can see more than one. Leaving $GOOD as the default."
    fi
    # Record the classes that were default, so the reset can put them back.
    if [ -z "$DEF_LIST" ]; then
      printf '%s\n' "none" > "$LABDIR/w9.sc.restore"
    else
      printf '%s\n' "$DEF_LIST" > "$LABDIR/w9.sc.restore"
    fi
    printf '%s\n' "$GOOD" > "$LABDIR/w9.sc.undefault"
    # Exactly one class may be the default at a time.
    for sc in $DEF_LIST; do
      if [ "$sc" = "$GOOD" ]; then continue; fi
      kubectl annotate storageclass "$sc" storageclass.kubernetes.io/is-default-class- --overwrite >/dev/null 2>&1 || true
    done
    kubectl annotate storageclass "$GOOD" storageclass.kubernetes.io/is-default-class=true --overwrite >/dev/null 2>&1 || true
    CHANGED="yes"
  fi
fi

EFFECTIVE_DEFAULT=""
if [ -n "$GOOD" ]; then
  EFFECTIVE_DEFAULT=$(default_classes | grep . | head -n 1 || true)
  if [ -z "$EFFECTIVE_DEFAULT" ]; then EFFECTIVE_DEFAULT="$GOOD"; fi
fi
EFFECTIVE_PROV=""
if [ -n "$EFFECTIVE_DEFAULT" ]; then
  EFFECTIVE_PROV=$(kubectl get storageclass "$EFFECTIVE_DEFAULT" -o jsonpath='{.provisioner}' 2>/dev/null || true)
fi

# ---- clean out anything a previous attempt left behind ---------------------
# The Pod owns the ephemeral claim, so deleting the Pod is what removes it.
# The garbage collector does the rest.

kubectl -n "$NS" delete pod --all --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1 || true
i=0
while [ "$i" -lt 30 ]; do
  LEFT=$(kubectl -n "$NS" get pvc --no-headers 2>/dev/null | grep -c . || true)
  [ "${LEFT:-0}" -eq 0 ] && break
  sleep 2
  i=$((i+2))
done
kubectl -n "$NS" delete pvc --all --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1 || true

echo "✅ w9 environment ready"
echo "   - namespace: $NS"
echo "   - default StorageClass: ${EFFECTIVE_DEFAULT:-<none>} (provisioner: ${EFFECTIVE_PROV:-<none>})"
echo "   - the cluster's own default classes: $(printf '%s' "$DEF_LIST" | tr '\n' ' ')"
if [ "$CHANGED" = "yes" ]; then
  echo "   - NOTE: the setup put $GOOD in place as the default class, because the cluster's own"
  echo "     default could not dynamically provision. './lab.sh w9 reset' puts the original back."
fi
echo "   - Task: give a Pod a volume of its own, and show that the claim belongs to the Pod"

if [ -z "$GOOD" ]; then
  echo "   ⚠️  There is no StorageClass that can provision, so the ephemeral claim will stay" >&2
  echo "      Pending and the Pod will not start. This question needs one." >&2
fi
