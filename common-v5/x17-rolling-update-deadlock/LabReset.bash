#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the Deployment and its pods, so deleting it removes
# everything the setup created and everything the candidate produced.
k delete namespace rollout --ignore-not-found --timeout=120s >/dev/null

rm -f /tmp/cka-lab/x17.deploy.uid /tmp/cka-lab/x17.image

echo "x17 reset: namespace rollout removed (Deployment and pods), the state files deleted"
