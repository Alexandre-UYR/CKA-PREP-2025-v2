#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The LimitRange and the Deployment both live in the namespace, and so does
# every pod the candidate may have created - deleting the namespace is the
# whole reset. Nothing survives it.
k delete namespace qos --ignore-not-found --timeout=120s >/dev/null

echo "v20 reset: namespace qos removed"
