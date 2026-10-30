#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the Deployment, the ConfigMap and the pods; deleting it
# removes all three.
k delete namespace probe --ignore-not-found --timeout=120s >/dev/null

# Remove the Deployment UID taken at setup.
rm -f /tmp/cka-lab/x19.dep.uid

echo "x19 reset: namespace probe removed, the Deployment UID file deleted"
