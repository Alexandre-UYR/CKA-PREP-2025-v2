#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the Deployment and its pod. The container's memory limit
# lives in the Deployment, so deleting the namespace removes it with everything
# else - nothing else survives a reset here.
k delete namespace oom --ignore-not-found --timeout=120s >/dev/null

echo "v4 reset: namespace oom removed"
