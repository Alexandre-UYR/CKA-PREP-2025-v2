#!/bin/bash
set -e

# v17 - The Job that will never finish
#
# The pre-state is a Job whose container exits 1 straight away. A Job's pods
# are never restarted, so every pod the Job creates fails for good. The Job
# keeps creating new pods until backoffLimit is exhausted, and only then does
# it take the Failed condition - which is where the candidate finds it.
#
# The namespace is recreated on every run, so a Job the candidate already
# fixed cannot answer the validation on its own.

NS=jobs
JOB=import

kubectl delete namespace "$NS" --ignore-not-found --timeout=120s
kubectl create namespace "$NS"

cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: $JOB
  namespace: $NS
  labels:
    app: $JOB
spec:
  completions: 3
  parallelism: 1
  backoffLimit: 2
  template:
    metadata:
      labels:
        app: $JOB
    spec:
      restartPolicy: Never
      containers:
        - name: importer
          image: busybox:1.36
          command: ["sh", "-c", "echo \"starting\"; exit 1"]
EOF

echo "Waiting for the Job to burn through its retries (backoffLimit 2 = three pod attempts)..."
FAILEDCOND=""
FAILEDPODS=""
i=0
while [ "$i" -lt 240 ]; do
  FAILEDCOND=$(kubectl -n "$NS" get job "$JOB" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null) || FAILEDCOND=""
  FAILEDPODS=$(kubectl -n "$NS" get job "$JOB" -o jsonpath='{.status.failed}' 2>/dev/null) || FAILEDPODS=""
  [ "$FAILEDCOND" = "True" ] && break
  sleep 5
  i=$((i+5))
done

PODS=$(kubectl -n "$NS" get pods -l "job-name=$JOB" \
         -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.status.phase}{"\n"}{end}' 2>/dev/null || true)

echo "✅ v17 environment ready"
echo "   - namespace: $NS"
echo "   - Job: $JOB (completions 3, parallelism 1, backoffLimit 2)"
echo "   - Job's Failed condition: ${FAILEDCOND:-<not set yet>}"
echo "   - pods failed so far: ${FAILEDPODS:-0}"
echo "   - the Job's pods:"
printf '%s\n' "$PODS" | sed 's/^/       /'
echo "   - Task: read the pod's logs, work out why the container exits, and"
echo "     replace the Job (its pod template is immutable) so that all three"
echo "     completions succeed"

if [ "$FAILEDCOND" != "True" ]; then
  echo "   ⚠️  The Job has not taken the Failed condition yet. Check:" >&2
  echo "      kubectl -n $NS describe job $JOB" >&2
  echo "      kubectl -n $NS get pods -l job-name=$JOB" >&2
fi
