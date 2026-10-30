#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the Deployments, the Services and the Ingress the
# candidate writes, so removing it removes the whole pre-state and the whole
# answer in one step.
k delete namespace ingress --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

echo "c13 reset: namespace ingress removed (Deployments app-a and app-b, Services"
echo "            app-a and app-b, and the Ingress went with it)"
