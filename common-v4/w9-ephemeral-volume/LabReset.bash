#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }
LABDIR=/tmp/cka-lab
NS=ephem

# The namespace holds the Pod and the ephemeral claim. Deleting the namespace
# deletes the Pod, and the claim goes with it: it is owned by the Pod and is
# garbage collected. Do not delete the claim by hand.
k delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# ---- the StorageClasses -----------------------------------------------------
# If the setup had to put a class in place as the default, the cluster's own
# default goes back and the class the setup promoted is un-defaulted.

if [ -f "$LABDIR/w9.sc.undefault" ]; then
  SC=$(cat "$LABDIR/w9.sc.undefault" 2>/dev/null)
  if [ -n "$SC" ]; then
    k annotate storageclass "$SC" storageclass.kubernetes.io/is-default-class- --overwrite >/dev/null 2>&1 || true
  fi
fi

if [ -f "$LABDIR/w9.sc.restore" ]; then
  RESTORE=$(cat "$LABDIR/w9.sc.restore" 2>/dev/null)
  if [ -n "$RESTORE" ] && [ "$RESTORE" != "none" ]; then
    for sc in $RESTORE; do
      k annotate storageclass "$sc" storageclass.kubernetes.io/is-default-class=true --overwrite >/dev/null 2>&1 || true
    done
  fi
fi

rm -f "$LABDIR/w9.sc.restore" "$LABDIR/w9.sc.undefault"

echo "w9 reset: namespace $NS removed"
echo "w9 reset: the ephemeral claim went with its Pod - it is not deleted by hand"
echo "w9 reset: the cluster's own default StorageClass was put back"
