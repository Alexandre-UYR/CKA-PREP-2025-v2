#!/bin/bash
set -e

echo "# For this lab you can just use the killercoda playground as it is, no adjustments needed"

# ---------------------------------------------------------------------------
# The task says the CRDs are "pre installed", so the pre-state has to really
# contain them. They are cluster-scoped: they live outside any namespace and
# they are deliberately NOT removed by the reset, because deleting a CRD
# destroys every Argo CD resource of that type in the cluster. Re-running this
# setup re-applies them idempotently (server-side apply).
# ---------------------------------------------------------------------------
CRD_URL="https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.0/manifests/crds/crds.yaml"

echo "🔹 Installing the Argo CD CRDs (pre-installed state)..."
if ! kubectl apply --server-side --force-conflicts -f "$CRD_URL"; then
  echo "❌ Could not install the Argo CD CRDs from $CRD_URL" >&2
  echo "   This question needs them in the pre-state: check network access to raw.githubusercontent.com." >&2
  exit 1
fi

echo "⏳ Waiting for the CRDs to be established..."
kubectl wait --for=condition=Established \
  crd/applications.argoproj.io crd/appprojects.argoproj.io --timeout=60s || true

echo "✅ Lab setup complete!"
echo "   - Argo CD CRDs are installed in the cluster (pre-installed state, cluster-scoped)"
echo "   - The reset leaves the CRDs in place on purpose; re-running the setup re-applies them"
echo "   - Task: add the argocd helm repo, create the argocd namespace, template the chart"
