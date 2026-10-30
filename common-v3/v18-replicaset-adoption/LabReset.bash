#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the orphaned ReplicaSet, the two pods and the
# ReplicaSet the candidate created to adopt them. Deleting it takes all of
# them.
k delete namespace adopt --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# A ReplicaSet the candidate may have created outside that namespace (for
# instance while trying the adoption out) is cleaned up as well.
k delete replicaset web-adopted --all-namespaces --ignore-not-found --timeout=60s >/dev/null 2>&1 || true

echo "v18 reset: namespace adopt removed"
