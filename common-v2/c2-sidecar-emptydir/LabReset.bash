#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The Deployment and the namespace both live in the cluster, and the candidate's
# sidecar lives inside the Deployment, so removing the two covers everything
# the question produces.
k -n sidecar delete deploy app --ignore-not-found --timeout=60s >/dev/null 2>&1 || true
k delete namespace sidecar --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

echo "c2 reset: namespace sidecar removed"
