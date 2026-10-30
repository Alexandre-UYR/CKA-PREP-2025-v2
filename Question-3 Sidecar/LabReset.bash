#!/bin/bash
set -uo pipefail

echo "🔄 Resetting Q3 (sidecar)..."

# The deployment the candidate edited (and the service that came with the lab).
kubectl delete deployment wordpress --ignore-not-found --timeout=120s
kubectl delete service wordpress --ignore-not-found --timeout=60s

# The UID captured at setup time.
rm -f /tmp/cka-lab/q3.deploy.uid

echo "✅ Q3 reset: deployment wordpress and service wordpress deleted, uid file removed."
