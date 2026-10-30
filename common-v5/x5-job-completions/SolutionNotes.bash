# 1. Look at the Job you have been given.
kubectl -n jobs get job import
# NAME    STATUS     COMPLETIONS   DURATION   AGE
# import  Complete   1/1           6s         6s
#
# One completion, one at a time - the defaults. That is what the task is
# asking you to change.

kubectl -n jobs get job import -o jsonpath='{.spec.completions}{" "}{.spec.parallelism}{" "}{.spec.backoffLimit}{"\n"}'
# 1 1 6

# 2. Try to edit it. This is where the task's hint comes from.
kubectl -n jobs edit job import
# error: unable to parse "job.yaml": error validating "job.yaml": error validating data:
#   ValidationError(Job.spec): unknown field "spec.template.spec.containers[0].command"
# error: job.batch "import" is invalid: spec.template: Forbidden: updates to
#   job spec for fields other than 'suspend' are forbidden
#
# The pod template is immutable. The Job has to be replaced.

# 3. Replace it: the same name, the same container, and the three numbers.
kubectl -n jobs delete job import
# job.batch "import" deleted

cat <<'EOF' | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: import
  namespace: jobs
  labels:
    app: import
spec:
  completions: 10
  parallelism: 5
  backoffLimit: 4
  template:
    metadata:
      labels:
        app: import
    spec:
      restartPolicy: Never
      containers:
        - name: importer
          image: busybox:1.36
          command: ["sh", "-c", "sleep 5"]
EOF
# job.batch/import created

# 4. Wait for the ten completions.
kubectl -n jobs wait --for=condition=complete job/import --timeout=300s
# job.batch/import condition met

kubectl -n jobs get job import
# NAME    STATUS     COMPLETIONS   DURATION   AGE
# import  Complete   10/10         12s        12s

kubectl -n jobs get pods -l job-name=import
# NAME            READY   STATUS      RESTARTS   AGE
# import-4nq8t    0/1     Succeeded   0          12s
# import-6p2vh    0/1     Succeeded   0          12s
# import-7zxdq    0/1     Succeeded   0          11s
# ...
# import-x5t9k    0/1     Succeeded   0          2s
#
# Ten pods, five at a time - two waves.

# 5. Check the three numbers are what you meant.
kubectl -n jobs get job import -o jsonpath='{.spec.completions}{" "}{.spec.parallelism}{" "}{.spec.backoffLimit}{"\n"}'
# 10 5 4
#
# A note on what did NOT work: editing the Job, or scaling it down and up, or
# deleting one of its pods to force a retry. The template is immutable, so the
# Job has to be re-created - and a Job that has already taken the Complete
# condition will not start the extra nine completions on its own.
