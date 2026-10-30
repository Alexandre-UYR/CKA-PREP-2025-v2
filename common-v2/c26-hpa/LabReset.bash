#!/bin/bash
# Reset for c26 (Horizontal autoscaling): back to the pre-state so the
# question can be attempted again from scratch.
set -uo pipefail
k(){ kubectl "$@"; }

NS=autoscale
HPA=web-hpa
DEPLOY=web
UID_FILE=/tmp/cka-lab/c26.uid

# The HPA the candidate created.
k delete hpa "$HPA" -n "$NS" --ignore-not-found >/dev/null 2>&1 || true

# The namespace takes the Deployment with it. Run the setup again afterwards to
# rebuild the pre-state.
k delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# The recorded UID belongs to a Deployment that no longer exists.
rm -f "$UID_FILE"

echo "c26 reset: HPA $HPA and namespace $NS removed, $UID_FILE deleted."
echo "         Run './lab.sh c26' to rebuild the pre-state."
