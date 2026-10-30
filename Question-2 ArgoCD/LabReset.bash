#!/bin/bash
set -uo pipefail

echo "🔄 Resetting Q2 (Argo CD)..."

# The manifest the candidate produced.
rm -f /root/argo-helm.yaml

# The namespace the candidate created.
kubectl delete namespace argocd --ignore-not-found --timeout=120s

# The helm repo the candidate added.
if command -v helm >/dev/null 2>&1; then
  helm repo remove argocd >/dev/null 2>&1 || true
fi

# The Argo CD CRDs are deliberately left in place: they are cluster-scoped and
# deleting a CRD destroys every Argo CD resource of that type in the cluster.
# The setup re-applies them, so re-running it is safe.

echo "✅ Q2 reset: /root/argo-helm.yaml removed, namespace argocd deleted, helm repo 'argocd' removed (CRDs left in place)."
