# 1. Look at the material you were given.
kubectl -n cron get configmap job-config -o yaml
# apiVersion: v1
# data:
#   MSG: hello-from-the-configmap
kubectl -n cron get serviceaccount
# NAME      SECRETS   AGE
# cron-sa   0         30s

# 2. Create the CronJob. Note where everything lives: the schedule on the
#    CronJob, the pod template under .spec.jobTemplate.spec.template.
cat <<'EOF' | kubectl apply -n cron -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: reporter
  namespace: cron
spec:
  schedule: "*/2 * * * *"
  concurrencyPolicy: Forbid
  startingDeadlineSeconds: 60
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: cron-sa
          restartPolicy: OnFailure
          containers:
            - name: reporter
              image: busybox:1.36
              env:
                - name: MSG
                  valueFrom:
                    configMapKeyRef:
                      name: job-config
                      key: MSG
              command: ["sh", "-c"]
              args:
                - "echo \"$(date -u) $MSG\" >> /out/report.txt && cat /out/report.txt"
              volumeMounts:
                - name: out
                  mountPath: /out
          volumes:
            - name: out
              emptyDir: {}
EOF

# 3. Check the spec you just wrote.
kubectl -n cron get cronjob reporter -o yaml
# ...schedule: "*/2 * * * *"
# ...concurrencyPolicy: Forbid
# ...startingDeadlineSeconds: 60

# 4. Trigger a run immediately, so you are not waiting up to two minutes for
#    the schedule to fire.
kubectl -n cron create job --from=cronjob/reporter reporter-manual
# job.batch/reporter-manual created

kubectl -n cron get job reporter-manual -w
# NAME             COMPLETIONS   DURATION   AGE
# reporter-manual   1/1           2s         5s

# 5. Confirm the Job actually completed, and look at what it wrote.
kubectl -n cron get job reporter-manual -o jsonpath='{.status.succeeded}{"\n"}'
# 1
kubectl -n cron logs job/reporter-manual
# 2026-10-30 19:41:02 hello-from-the-configmap

# A note on the two knobs the task asks for:
#   concurrencyPolicy: Forbid  - do not start a run while another is going
#   startingDeadlineSeconds: 60 - a scheduled run that is more than a minute
#                                 late is skipped rather than fired late
# A note on the volume: /out is an emptyDir, so the report lives as long as
# the pod does - the CronJob's own copy of it is gone when the pod exits.
