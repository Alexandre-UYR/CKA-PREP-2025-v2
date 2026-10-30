#!/bin/bash
# Reset for Question 5 (HPA): back to the pre-state so the question can be
# attempted again from scratch.
set -uo pipefail
k(){ kubectl "$@"; }

# The HPA the candidate created.
k delete hpa apache-server -n autoscale --ignore-not-found >/dev/null 2>&1 || true

# The namespace holds the deployment and the service the candidate was given.
k delete namespace autoscale --ignore-not-found >/dev/null 2>&1 || true

# metrics-server lives in kube-system, so deleting the namespace above does not
# touch it. It was installed by LabSetUp.bash, so remove it here as well --
# otherwise it is left behind in the cluster after a reset.
k delete deployment metrics-server -n kube-system --ignore-not-found >/dev/null 2>&1 || true

echo "Q5 reset: HPA apache-server, namespace autoscale and the metrics-server deployment are gone."
