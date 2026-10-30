#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# Everything the candidate produces lives in the namespace, but the three
# objects are deleted explicitly as well so that the reset is safe to run
# against a cluster where the namespace has already gone.
k -n config delete deploy app --ignore-not-found --timeout=60s >/dev/null 2>&1 || true
k -n config delete secret app-secret --ignore-not-found --timeout=60s >/dev/null 2>&1 || true
k -n config delete configmap app-config --ignore-not-found --timeout=60s >/dev/null 2>&1 || true
k delete namespace config --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

echo "c4 reset: namespace config removed"
