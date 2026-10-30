#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

STATE=/tmp/cka-lab

# Deleting the CRD deletes every Widget it owns, so this is enough to wipe the
# candidate's custom resources as well.
k delete crd widgets.example.com --ignore-not-found --timeout=120s >/dev/null 2>&1

k delete namespace custom --ignore-not-found --timeout=120s >/dev/null 2>&1

# The manifests the candidate was asked to save live on disk, not in the
# cluster, so they have to be removed by hand.
rm -f "$STATE/c22.crd.yaml" "$STATE/c22.widget.yaml"

echo "c22 reset: CRD widgets.example.com, namespace custom and $STATE/c22.crd.yaml removed"
