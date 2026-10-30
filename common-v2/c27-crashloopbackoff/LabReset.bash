#!/bin/bash
# Reset for c27 (a pod that will not stay up): back to the pre-state so the
# question can be attempted again from scratch.
set -uo pipefail
k(){ kubectl "$@"; }

NS=broken
POD=worker
BEFORE_FILE=/tmp/cka-lab/c27.pod.before

# The namespace takes the broken Pod with it. Run the setup again afterwards
# to rebuild the pre-state.
k delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# In case the namespace was already gone and the Pod was re-created outside
# it, clean up by name too.
k delete pod "$POD" -n "$NS" --ignore-not-found >/dev/null 2>&1 || true

# The recorded creationTimestamp belongs to a Pod that no longer exists.
rm -f "$BEFORE_FILE"

echo "c27 reset: namespace $NS removed, $BEFORE_FILE deleted."
echo "         Run './lab.sh c27' to rebuild the broken pre-state."
