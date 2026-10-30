#!/bin/bash
set -e

# x5 - Ten of them, five at a time
#
# The pre-state is a Job with the DEFAULT settings: no completions, no
# parallelism, no backoffLimit, so the API server fills in 1, 1 and 6. It runs
# its work once, one pod at a time, and completes.
#
# The namespace is recreated on every run, so a Job the candidate already
# replaced cannot answer the validation on its own.

NS=jobs
JOB=import

kubectl delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
kubectl create namespace "$NS"

# No completions, no parallelism, no backoffLimit: the defaults apply.
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: $JOB
  namespace: $NS
  labels:
    app: $JOB
spec:
  template:
    metadata:
      labels:
        app: $JOB
    spec:
      restartPolicy: Never
      containers:
        - name: importer
          image: busybox:1.36
          command: ["sh", "-c", "sleep 5"]
EOF

echo "Waiting for the Job to complete its one default completion..."
SUCC=""
COMPLETE=""
i=0
while [ "$i" -lt 120 ]; do
  SUCC=$(kubectl -n "$NS" get job "$JOB" -o jsonpath='{.status.succeeded}' 2>/dev/null || true)
  COMPLETE=$(kubectl -n "$NS" get job "$JOB" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || true)
  if [ "$SUCC" = "1" ] && [ "$COMPLETE" = "True" ]; then break; fi
  sleep 2
  i=$((i+2))
done

COMPL=$(kubectl -n "$NS" get job "$JOB" -o jsonpath='{.spec.completions}' 2>/dev/null || true)
PARA=$(kubectl -n "$NS" get job "$JOB" -o jsonpath='{.spec.parallelism}' 2>/dev/null || true)
BO=$(kubectl -n "$NS" get job "$JOB" -o jsonpath='{.spec.backoffLimit}' 2>/dev/null || true)

echo "✅ x5 environment ready"
echo "   - namespace: $NS"
echo "   - Job: $JOB"
echo "   - completions: ${COMPL:-<unset>}, parallelism: ${PARA:-<unset>}, backoffLimit: ${BO:-<unset>}"
echo "   - successful completions so far: ${SUCC:-0}"
echo "   - Complete condition: ${COMPLETE:-<not set yet>}"
echo "   - Task: replace it with a Job that has a backoffLimit set,"
echo "     completions 10 and parallelism 5, running the same container, and"
echo "     get it to all ten successful completions"

if [ "$SUCC" != "1" ] || [ "$COMPLETE" != "True" ]; then
  echo "   ⚠️  The Job has not completed its default run yet." >&2
  echo "      Check: kubectl -n $NS get job $JOB" >&2
fi
