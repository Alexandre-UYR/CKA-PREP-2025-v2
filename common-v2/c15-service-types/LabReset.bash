#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the Deployment and all three Services, so removing it
# removes everything the question produced.
k delete namespace svctypes --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

echo "c15 reset: namespace svctypes removed"
