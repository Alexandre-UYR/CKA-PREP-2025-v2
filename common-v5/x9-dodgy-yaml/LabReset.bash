#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

NS=dodgy
LABDIR=/tmp/cka-lab
MANIFEST="$LABDIR/dodgy.yaml"

# The namespace holds the Service and the Deployment the candidate applied.
k delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# The manifest is a file the setup handed to the candidate, and the candidate
# was supposed to edit it in place - so it goes, and the next attempt starts
# from the broken original again.
rm -f "$MANIFEST"

echo "x9 reset: namespace $NS removed, $MANIFEST deleted"
echo "          (the next run of the setup writes the broken manifest again)"
