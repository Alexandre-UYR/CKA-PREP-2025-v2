#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the ResourceQuota, the LimitRange and the Deployment
# the candidate wrote, so deleting it removes all of it - nothing else
# survives a reset here.
k delete namespace quota --ignore-not-found --timeout=120s >/dev/null

echo "v16 reset: namespace quota removed"
