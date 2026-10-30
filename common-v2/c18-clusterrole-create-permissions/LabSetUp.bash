#!/bin/bash
set -e

# Pre-state for c18: a namespace and a ServiceAccount in it.
#
# There is no ClusterRole and no binding yet - the whole question is to write
# one that grants exactly one verb and to prove it with `kubectl auth can-i`.

NS=ops

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: builder
  namespace: ops
EOF

echo "✅ c18 environment ready"
echo "   - namespace: $NS"
echo "   - ServiceAccount: builder"
echo "   - Task: create a ClusterRole granting exactly one verb and bind it to builder"
