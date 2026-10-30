#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the Deployment and its pod. Every volume the candidate
# adds lives inside the pod, so deleting the namespace removes the sidecar,
# the shared volume and anything the candidate produced with them.
k delete namespace sidecar --ignore-not-found --timeout=120s >/dev/null

echo "v1 reset: namespace sidecar removed"
