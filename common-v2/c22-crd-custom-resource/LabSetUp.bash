#!/bin/bash
set -e

# The pre-state for c22 is thin on purpose: the task is to DEFINE a CRD and
# use it, so there is no broken CRD to reproduce. What has to exist is the
# namespace the task names.
#
# The setup also clears anything a previous attempt left behind - the CRD and
# the manifest file - so a re-run always starts from the same place.
NS=custom
STATE=/tmp/cka-lab

mkdir -p "$STATE"

# Deleting the CRD deletes every Widget it owns, so this is enough to wipe a
# previous attempt's custom resources as well.
kubectl delete crd widgets.example.com --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

rm -f "$STATE/c22.crd.yaml"

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

echo "✅ c22 environment ready"
echo "   - namespace: $NS"
echo "   - workdir: $STATE (save your CRD manifest there as c22.crd.yaml)"
echo "   - Task: define the CRD widgets.example.com and create a Widget 'w1'"
