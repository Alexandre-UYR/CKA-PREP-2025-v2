#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the ConfigMap, the Deployment, the init container and
# the pod. Everything the candidate adds lives inside them, so deleting the
# namespace restores the starting point exactly.
k delete namespace init --ignore-not-found --timeout=120s >/dev/null

echo "v2 reset: namespace init removed"
