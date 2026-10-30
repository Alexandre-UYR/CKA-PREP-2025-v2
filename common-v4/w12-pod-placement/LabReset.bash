#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

NS=place
LABDIR=/tmp/cka-lab
STATE="$LABDIR/w12.node"

# The namespace holds the three Pods; deleting it removes them.
k delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# The state file is the setup's, not the candidate's.
rm -f "$STATE"

# The workload=general label stays on the node: it is part of the pre-state
# the setup creates, and the setup re-applies it on the next run.

echo "w12 reset: namespace $NS removed and $STATE deleted"
