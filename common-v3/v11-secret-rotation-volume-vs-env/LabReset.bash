#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# Everything lives in the `rot` namespace: the Secret, the Deployment, its pod,
# and anything the candidate changed or created. Deleting the namespace removes
# all of it, and nothing here survives the namespace.
k delete namespace rot --ignore-not-found --timeout=120s >/dev/null

echo "v11 reset: namespace rot removed"
