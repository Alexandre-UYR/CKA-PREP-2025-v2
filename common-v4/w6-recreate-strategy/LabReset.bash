#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }
LABDIR=/tmp/cka-lab

# The namespace holds the Deployment and its pods; deleting it removes both.
k delete namespace cka4 --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# The answer file is on disk, not in the cluster, so it has to be removed by
# hand. The recorded UID goes with it - the next setup records a new one.
rm -f /root/q4.yaml "$LABDIR/w6.dep.uid"

echo "w6 reset: namespace cka4 removed, /root/q4.yaml and the recorded UID deleted"
