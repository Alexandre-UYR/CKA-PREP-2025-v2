#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# Everything lives in the `ing` namespace: the api, its Service, the two TLS
# secrets, and the Ingress the candidate writes.
k delete namespace ing --ignore-not-found --timeout=120s >/dev/null

echo "v13 reset: namespace ing removed"
