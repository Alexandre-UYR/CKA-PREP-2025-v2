#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the Deployment and its pod. The probes live in the
# pod template, so deleting the namespace removes the candidate's startup
# probe and any change to the liveness probe as well.
k delete namespace probe --ignore-not-found --timeout=120s >/dev/null

echo "v3 reset: namespace probe removed"
