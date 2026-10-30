#!/bin/bash
set -e

# x11 - Prove it with the credentials
#
# The pre-state is a namespace with a ServiceAccount in it and no permissions
# at all. The candidate has to grant that ServiceAccount exactly one thing -
# list the Pods in its own namespace - and then prove the grant with the
# ServiceAccount's own credentials rather than with their own.
#
# The namespace is re-created on every run, so a Role or a RoleBinding left
# behind by a previous attempt does not survive, and the starting state is
# always the same.

NS=rbac
SA=admin
KUBECONFIG_OUT=/root/rbac.kubeconfig

kubectl delete namespace "$NS" --ignore-not-found --timeout=180s >/dev/null 2>&1 || true
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NS" create serviceaccount "$SA" --dry-run=client -o yaml | kubectl apply -f -

# The kubeconfig is the candidate's output. A leftover from a previous attempt
# would make the exercise look solved before it is.
rm -f "$KUBECONFIG_OUT" 2>/dev/null || true

echo "Waiting for the ServiceAccount to be created..."
i=0
while [ "$i" -lt 30 ]; do
  if kubectl -n "$NS" get serviceaccount "$SA" >/dev/null 2>&1; then break; fi
  sleep 1
  i=$((i+1))
done

echo "x11 environment ready"
echo "   - namespace: $NS"
echo "   - ServiceAccount: $SA (no permissions yet, no token Secret either)"
echo "   - no Role and no RoleBinding exist"
echo "   - $KUBECONFIG_OUT does not exist yet"
echo "   - Task: grant the ServiceAccount list on pods in $NS and nothing else,"
echo "     then mint a token for it and prove the boundary with a kubeconfig"
