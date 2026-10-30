#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the ConfigMap and the Deployment; deleting it removes
# both, and with them anything the candidate built on top of them.
k delete namespace cfg --ignore-not-found --timeout=120s >/dev/null

# The files live on the machine, not in the cluster, so they have to be
# removed by hand.
rm -rf /tmp/cka-lab/colors

echo "w14 reset: namespace cfg removed, /tmp/cka-lab/colors deleted"
