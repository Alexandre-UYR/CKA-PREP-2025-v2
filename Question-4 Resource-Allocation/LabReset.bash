#!/bin/bash
set -uo pipefail

echo "🔄 Resetting Q4 (resource allocation)..."

# Put the replicas back first, so nothing is left scaled to 0 if the deletion
# below fails.
kubectl scale deployment wordpress --replicas=3 --ignore-not-found >/dev/null 2>&1 || true

# The deployment is deleted on purpose: the setup creates it again with 3
# replicas and with no resource requests or limits set.
kubectl delete deployment wordpress --ignore-not-found --timeout=120s

# UID files captured at setup time.
rm -f /tmp/cka-lab/q3.deploy.uid
rm -f /tmp/cka-lab/q4.deploy.uid

echo "✅ Q4 reset: deployment wordpress deleted (the setup recreates it at 3 replicas with no resources set)."
