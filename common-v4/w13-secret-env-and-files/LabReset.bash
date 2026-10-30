#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

NS=secrets

# The namespace holds the Secret and the Deployment the candidate created;
# deleting it removes both.
k delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

echo "w13 reset: namespace $NS removed"
