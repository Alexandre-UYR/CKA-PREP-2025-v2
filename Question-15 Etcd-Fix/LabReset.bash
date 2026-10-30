#!/bin/bash
set -uo pipefail

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

MANIFEST=/etc/kubernetes/manifests/kube-apiserver.yaml
PRISTINE=/root/kube-apiserver.yaml.pristine
BAK=/root/kube-apiserver.yaml.bak

SRC=""
if [ -s "$PRISTINE" ]; then
  SRC="$PRISTINE"
elif [ -s "$BAK" ]; then
  SRC="$BAK"
fi

if [ -n "$SRC" ]; then
  # Put the manifest back into its BROKEN state: that is the starting state of
  # this question, so a reset has to restore the breakage, not the health.
  $SUDO cp "$SRC" "$MANIFEST"
  $SUDO sed -i 's/:2379/:2380/g' "$MANIFEST"
  echo "Restored the broken kube-apiserver manifest from $SRC (etcd peer port 2380)."
else
  echo "WARNING: no pristine copy of the manifest was found, so the manifest was left as it is." >&2
fi

echo "Q15 reset"
echo "NOTE: the API server will fail to start again within a few seconds. That is the"
echo "      intended starting state for this question."
