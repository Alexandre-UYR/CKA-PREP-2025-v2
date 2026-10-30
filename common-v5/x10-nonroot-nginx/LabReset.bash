#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

LABDIR=/tmp/cka-lab

# The namespace holds the Pod and the ConfigMap, and whatever the candidate
# built on top of them.
k delete namespace sec --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# The configuration the setup staged on disk for the ConfigMap.
rm -f "$LABDIR/nginx.conf"

echo "x10 reset: namespace sec removed, the staged nginx.conf deleted"
