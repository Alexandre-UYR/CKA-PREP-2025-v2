#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace takes the Service, the Deployment, the StatefulSet, the pods
# and the PVCs with it.
k delete namespace stateful --ignore-not-found --timeout=120s >/dev/null

# A PersistentVolume with the Retain reclaim policy survives its namespace.
# Delete the ones this lab bound, so the next attempt starts from the same
# pool of disks.
k get pv -o jsonpath='{range .items[?(@.spec.claimRef.namespace=="stateful")]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
  | while IFS= read -r pv; do
      [ -n "$pv" ] || continue
      k delete pv "$pv" --ignore-not-found >/dev/null 2>&1 || true
    done

echo "v6 reset: namespace stateful removed, and the PersistentVolumes bound into it deleted"
