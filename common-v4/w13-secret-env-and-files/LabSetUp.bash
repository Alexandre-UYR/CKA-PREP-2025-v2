#!/bin/bash
set -e

# w13 - The same Secret, two ways
#
# The pre-state is a namespace and a Secret, and nothing else. The candidate
# has to build a Deployment that reads the Secret twice - once into the
# environment, once onto the filesystem - and then show that both work from
# inside the container.
#
# The namespace is recreated on every run, so the setup is idempotent and the
# starting state is always the same.

NS=secrets
SEC=app-secret

kubectl delete namespace "$NS" --ignore-not-found --timeout=180s >/dev/null 2>&1 || true
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

# The Secret, with the two keys and nothing else. The values are plain so
# that the validator can check what the pod actually sees.
kubectl -n "$NS" create secret generic "$SEC" \
  --from-literal=username=admin \
  --from-literal=password=s3cr3t \
  --dry-run=client -o yaml | kubectl apply -f -

KEYS=$(kubectl -n "$NS" get secret "$SEC" -o go-template='{{len .data}}' 2>/dev/null || true)

if [ "${KEYS:-0}" != "2" ]; then
  echo "   WARN: the Secret $SEC holds ${KEYS:-0} keys, expected 2." >&2
  echo "         Check: kubectl -n $NS describe secret $SEC" >&2
fi

echo "w13 environment ready"
echo "   - namespace: $NS"
echo "   - Secret $SEC: username=admin, password=s3cr3t"
echo "   - nothing else in the namespace"
echo "   - Task: create a Deployment 'secret' that exports both keys as"
echo "     environment variables AND mounts both keys at /etc/secret, then"
echo "     show the variables and the files from inside the pod"
