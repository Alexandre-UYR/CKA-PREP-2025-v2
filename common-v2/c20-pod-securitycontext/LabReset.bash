#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The Pod first (it is the thing the candidate created), then the namespace.
# --ignore-not-found everywhere, so running the reset twice is harmless.
k delete pod restricted -n secure --ignore-not-found --timeout=60s >/dev/null 2>&1
k delete namespace secure --ignore-not-found --timeout=120s >/dev/null 2>&1

echo "c20 reset: namespace secure removed"
