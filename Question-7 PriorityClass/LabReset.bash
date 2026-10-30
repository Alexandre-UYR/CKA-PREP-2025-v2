#!/bin/bash
# Reset for Question 7 (PriorityClass): back to the pre-state so the question
# can be attempted again from scratch.
set -uo pipefail
k(){ kubectl "$@"; }

# The PriorityClass the candidate created.
k delete priorityclass high-priority --ignore-not-found >/dev/null 2>&1 || true

# The namespace holds the busybox-logger deployment.
k delete namespace priority --ignore-not-found >/dev/null 2>&1 || true

# The deployment uid captured at setup time.
rm -f /tmp/cka-lab/q7.deploy.uid 2>/dev/null || true

# DELIBERATELY NOT deleting the user-critical PriorityClass. It is the
# cluster-wide pre-state the question refers to ("the cluster already has at
# least one user defined Priority Class"), and LabSetUp.bash re-creates it
# idempotently.
echo "Q7 reset: PriorityClass high-priority, namespace priority and /tmp/cka-lab/q7.deploy.uid removed (user-critical left in place)."
