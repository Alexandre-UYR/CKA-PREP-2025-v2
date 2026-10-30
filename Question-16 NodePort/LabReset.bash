#!/bin/bash
# Reset for Question 16 (NodePort): back to the pre-state so the question can
# be attempted again from scratch.
set -uo pipefail
k(){ kubectl "$@"; }

# Deleting the namespace removes both the deployment and the Service.
k delete namespace relative --ignore-not-found >/dev/null 2>&1 || true

# Any lab scratch files under /tmp/cka-lab for this question.
rm -f /tmp/cka-lab/q16.* 2>/dev/null || true

echo "Q16 reset: namespace relative (deployment nodeport-deployment and Service nodeport-service) removed."
