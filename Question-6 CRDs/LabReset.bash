#!/bin/bash
# Reset for Question 6 (CRDs): back to the pre-state so the question can be
# attempted again from scratch.
set -uo pipefail
k(){ kubectl "$@"; }

# The two files the candidate was supposed to produce. They live in /root, so
# they may need sudo to remove. `sudo -n` keeps the reset from hanging on a
# password prompt.
rm -f /root/resources.yaml /root/subject.yaml 2>/dev/null || true
sudo -n rm -f /root/resources.yaml /root/subject.yaml 2>/dev/null || true

# The namespace holds the minimal cert-manager deployment.
k delete namespace cert-manager --ignore-not-found >/dev/null 2>&1 || true

# DELIBERATELY NOT deleting the cert-manager CRDs. They are cluster-scoped, and
# deleting them would destroy every Certificate object in the cluster --
# including ones that have nothing to do with this lab. LabSetUp.bash re-applies
# them idempotently, so the pre-state is already intact.
echo "Q6 reset: namespace cert-manager, /root/resources.yaml and /root/subject.yaml removed (cert-manager CRDs left in place)."
