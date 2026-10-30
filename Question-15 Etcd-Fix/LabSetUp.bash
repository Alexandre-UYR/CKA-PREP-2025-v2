#!/bin/bash
set -e

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

MANIFEST=/etc/kubernetes/manifests/kube-apiserver.yaml
PRISTINE=/root/kube-apiserver.yaml.pristine
BAK=/root/kube-apiserver.yaml.bak

# Keep one pristine copy of the working manifest. Both the setup and the reset
# build on it, so the question can be run again and again without the backup
# slowly turning into a copy of the broken manifest.
if [ ! -s "$PRISTINE" ]; then
  if ! $SUDO grep -q ':2379' "$MANIFEST"; then
    echo "ERROR: $MANIFEST does not reference the etcd client port 2379 and no pristine copy exists." >&2
    echo "       The control plane looks broken already. Fix it by hand before running the setup." >&2
    exit 1
  fi
  $SUDO cp "$MANIFEST" "$PRISTINE"
  $SUDO cp "$MANIFEST" "$BAK"
fi

# Start from the pristine manifest, then break it.
$SUDO cp "$PRISTINE" "$MANIFEST"

# Simulate the migration issue: point the apiserver at the etcd PEER port 2380.
$SUDO sed -i 's/:2379/:2380/g' "$MANIFEST"

echo "kube-apiserver manifest now points at the etcd peer port 2380."
echo "Current etcd flag:"
$SUDO grep -o 'etcd-servers=[^ ]*' "$MANIFEST" || true

# Show the apiserver container. It will be crash-looping.
echo
echo "Checking kube-apiserver container..."
KAPISERVER_ID=$($SUDO crictl ps -a 2>/dev/null | grep kube-apiserver | awk '{print $1}' | head -n 1)
if [ -n "$KAPISERVER_ID" ]; then
  $SUDO crictl logs "$KAPISERVER_ID" 2>/dev/null | tail -n 10 || true
else
  echo "kube-apiserver container not found yet"
fi

# Verify that kubectl fails: the API server is down due to the misconfigured etcd client port.
echo
if kubectl get nodes --request-timeout=15s >/dev/null 2>&1; then
  echo "WARNING: kubectl still works. The apiserver may not have noticed the change yet."
else
  echo "As expected, the API server is down due to the misconfigured etcd client port."
fi
