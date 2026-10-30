#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The Service and the Deployment both live in the namespace, and the
# candidate's container port lives inside the Deployment, so removing the two
# covers everything the question produces.
k -n namedport delete svc web-svc --ignore-not-found --timeout=60s >/dev/null 2>&1 || true
k -n namedport delete deploy web --ignore-not-found --timeout=60s >/dev/null 2>&1 || true
k delete namespace namedport --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

echo "c3 reset: namespace namedport removed"
