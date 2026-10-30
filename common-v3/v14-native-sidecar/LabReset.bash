#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the Deployment, its pod and the emptyDir volume. The
# emptyDir lives and dies with the pod, so deleting the namespace removes
# everything - nothing else survives a reset here.
k delete namespace sidecars --ignore-not-found --timeout=120s >/dev/null

echo "v14 reset: namespace sidecars removed"
