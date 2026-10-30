#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

NS=edge
LABDIR=/tmp/cka-lab
UIDFILE="$LABDIR/x6.svc.uid"

# The namespace holds the Deployment, the Service the candidate edited, and
# any throwaway pod the validator left behind - deleting it removes all three.
k delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# The state file the setup wrote. The Service's UID lives in it, and it only
# means anything while the Service does.
rm -f "$UIDFILE"

echo "x6 reset: namespace $NS removed, the Service UID file deleted"
echo "          (nothing outside the namespace was changed - a NodePort leaves"
echo "           no trace on the node once the Service is gone)"
