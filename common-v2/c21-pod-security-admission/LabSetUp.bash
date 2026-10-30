#!/bin/bash
set -e

# The pre-state for c21 is a namespace with NO Pod Security Admission labels.
#
# The setup removes the namespace first and recreates it, so a re-run takes back
# the "restricted" enforcement the candidate added and drops the Pods they
# created inside it. Removing first (rather than patching the labels away)
# also guarantees the namespace really is back to its pre-state.
NS=psa-test

kubectl delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# A namespace can get stuck in Terminating if something else holds a finalizer
# on it. Clearing the finalizer lets the delete finish, otherwise the recreate
# below would land on a namespace that is on its way out.
if kubectl get namespace "$NS" >/dev/null 2>&1; then
  kubectl patch namespace "$NS" --type=merge -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1 || true
  i=0
  while [ $i -lt 30 ] && kubectl get namespace "$NS" >/dev/null 2>&1; do
    i=$((i+1)); sleep 2
  done
fi

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

echo "✅ c21 environment ready"
echo "   - namespace: $NS (no pod-security.kubernetes.io labels)"
echo "   - Task: make the namespace ENFORCE the restricted Pod Security Standard"
