#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

NS=release
UIDFILE=/tmp/cka-lab/c25.uid

# The namespace holds the Deployment `api`, its ReplicaSets and its pods.
# Removing it removes the whole pre-state and the whole answer at once.
k delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# The state file the setup wrote. It has to go too, so that the next setup
# records the UID of the Deployment it creates rather than a stale one.
rm -f "$UIDFILE"

echo "c25 reset: namespace $NS removed and the recorded UID file deleted"
