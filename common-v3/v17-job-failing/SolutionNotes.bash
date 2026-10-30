# 1. Look at the Job.
kubectl -n jobs get job import
# NAME    STATUS     COMPLETIONS   DURATION   AGE
# import  Failed     0/3           36s        36s
#
# STATUS Failed means the Job gave up: the number of failed pods exceeded
# backoffLimit (2), so there were three pod attempts, all of them failures.

kubectl -n jobs describe job import
#   Status:
#     Failed: 3
#     Conditions:
#       Type: Failed
#         Status: True
#         Reason: BackoffLimitExceeded
#         Message: Job has reached the specified backoff limit
#   Events:
#     Warning  BackoffLimitExceeded  ...  Job has reached the specified backoff limit

# 2. The reason is in the pods. Which pods?
kubectl -n jobs get pods -l job-name=import
# NAME            READY   STATUS      RESTARTS   AGE
# import-6v4k8    0/1     Failed      0          30s
# import-9dtqp    0/1     Failed      0          20s
# import-xm2lb    0/1     Failed      0          5s

# 3. Read one of them.
kubectl -n jobs logs import-6v4k8
# starting
#
# That is all there is: the container prints one line and stops. The exit
# code says why.
kubectl -n jobs describe pod import-6v4k8
#   State:          Terminated
#     Reason:       Error
#     Exit Code:    1
#
# The container's command is the fault: `sh -c 'echo "starting"; exit 1'`
# exits 1 the moment it starts, so every pod the Job creates fails.

kubectl -n jobs get job import -o jsonpath='{.spec.template.spec.containers[0].command}' && echo
# ["sh","-c","echo \"starting\"; exit 1"]

# 4. Try to edit it - this is where the task's hint comes from.
kubectl -n jobs edit job import
# error: unable to parse "job.yaml": ...
#   error: job.batch "import" is invalid: spec.template: Forbidden:
#   updates to job spec for fields other than 'suspend' are forbidden
#
# The pod template is immutable. The Job has to be replaced.

# 5. Replace it: same name, same completion count, backoffLimit no higher
#    than 2, and a command that exits 0.
kubectl -n jobs delete job import
# job.batch "import" deleted

cat <<'EOF' | kubectl -n jobs apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: import
  namespace: jobs
  labels:
    app: import
spec:
  completions: 3
  parallelism: 1
  backoffLimit: 2
  template:
    metadata:
      labels:
        app: import
    spec:
      restartPolicy: Never
      containers:
        - name: importer
          image: busybox:1.36
          command: ["sh", "-c", "echo \"imported\"; exit 0"]
EOF
# job.batch/import created

# 6. Wait for the three completions.
kubectl -n jobs wait --for=condition=complete job/import --timeout=180s
# job.batch/import condition met

kubectl -n jobs get job import
# NAME    STATUS     COMPLETIONS   DURATION   AGE
# import  Complete   3/3           6s         6s

kubectl -n jobs get pods -l job-name=import
# NAME            READY   STATUS      RESTARTS   AGE
# import-6v4k8    0/1     Succeeded   0          5s
# import-9dtqp    0/1     Succeeded   0          3s
# import-xm2lb    0/1     Succeeded   0          1s

kubectl -n jobs logs job/import
# imported
#
# A note on what did NOT work: editing the Job, or scaling it down and up,
# or deleting a pod to force a retry. The template is immutable, so the Job
# has to be re-created - and a Job that has already taken the Failed
# condition will not restart its work on its own.
