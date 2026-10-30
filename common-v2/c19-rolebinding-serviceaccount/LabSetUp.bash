#!/bin/bash
set -e

# Pre-state for c19: a namespace and a ServiceAccount in it.
#
# There is no Role and no RoleBinding yet - the whole question is to write a
# namespaced read grant for pods, bind it to the ServiceAccount, and prove the
# grant stops at the namespace boundary.

NS=audit

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: auditor
  namespace: audit
EOF

echo "✅ c19 environment ready"
echo "   - namespace: $NS"
echo "   - ServiceAccount: auditor"
echo "   - Task: create a Role that reads pods and a RoleBinding to auditor"
