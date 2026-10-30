#!/bin/bash
set -e

# v7 - Something on a schedule
#
# The pre-state is the material the CronJob has to consume: a ConfigMap with
# the message to write, and a ServiceAccount for the job to run as. The
# namespace is recreated on every run, so no Job or CronJob from a previous
# attempt is left behind to confuse the answer.
#
# The namespace, the ConfigMap and the ServiceAccount are recreated on every
# run, so the setup is idempotent and the starting state is always the same.

NS=cron
CM=job-config
SA=cron-sa

kubectl delete namespace "$NS" --ignore-not-found --timeout=120s
kubectl create namespace "$NS"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: $CM
  namespace: $NS
  labels:
    app: $CM
data:
  MSG: hello-from-the-configmap
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $SA
  namespace: $NS
  labels:
    app: $SA
EOF

# The default StorageClass is part of the material on offer: it is what a
# candidate would reach for if the job had to write to durable storage. The
# task itself only needs an emptyDir.
DEFAULT_SC=$(kubectl get storageclass \
  -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -1)

MSG=$(kubectl -n "$NS" get configmap "$CM" -o jsonpath='{.data.MSG}' 2>/dev/null || true)
SA_OK=$(kubectl -n "$NS" get serviceaccount "$SA" -o jsonpath='{.metadata.name}' 2>/dev/null || true)

echo "✅ v7 environment ready"
echo "   - namespace: $NS"
echo "   - ConfigMap: $CM (key MSG = ${MSG:-<missing>})"
echo "   - ServiceAccount: ${SA_OK:-<missing>}"
echo "   - default StorageClass: ${DEFAULT_SC:-<none>}"
echo "   - CronJob: none yet - the candidate creates 'reporter'"
echo "   - Task: schedule the job every two minutes, write the ConfigMap's MSG into /out, and prove a run completes"

if [ "$MSG" != "hello-from-the-configmap" ]; then
  echo "   ⚠️  The ConfigMap key MSG is not what it should be. Check:" >&2
  echo "      kubectl -n $NS get configmap $CM -o yaml" >&2
fi
if [ -z "$SA_OK" ]; then
  echo "   ⚠️  The ServiceAccount $SA is missing. Check:" >&2
  echo "      kubectl -n $NS get serviceaccount" >&2
fi
