#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the example Deployment and the Pod the candidate
# created; deleting it removes both.
k delete namespace multi --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# No file is graded in this question, so there is nothing on disk to remove.
# A candidate who wrote notes is free to keep them.

echo "w3 reset: namespace multi removed (Deployment single and Pod multi-pod gone)"
