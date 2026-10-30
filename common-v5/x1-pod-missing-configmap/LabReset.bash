#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the Pod and the decoy ConfigMap; deleting it removes both.
k delete namespace diag --ignore-not-found --timeout=120s >/dev/null

# The ConfigMap the candidate created is in the namespace, so it goes with it,
# but remove it by name too in case it was created somewhere else.
k delete configmap app-config --all-namespaces --ignore-not-found >/dev/null 2>&1 || true

rm -f /tmp/cka-lab/x1.pod.uid

echo "x1 reset: namespace diag removed, the state file deleted"
