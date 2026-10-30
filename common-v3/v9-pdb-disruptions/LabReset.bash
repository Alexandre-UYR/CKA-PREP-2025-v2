#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the Deployment, its pods and the PodDisruptionBudget the
# candidate writes. Deleting the namespace removes all of it. Nothing here
# outlives the namespace, so the reset is a single delete.

k delete namespace pdb --ignore-not-found --timeout=120s >/dev/null

echo "v9 reset: namespace pdb removed"
