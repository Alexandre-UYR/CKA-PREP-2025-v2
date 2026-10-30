# Question: Something on a schedule
#
# The `cron` namespace already holds a ConfigMap `job-config` (key `MSG`) and a
# ServiceAccount `cron-sa`. There is no CronJob yet.
#
# Task:
# 1. Create a CronJob `reporter` in namespace `cron` that runs every two
#    minutes, on the schedule `*/2 * * * *`.
# 2. It must use the image `busybox:1.36` and the ServiceAccount `cron-sa`.
# 3. On each run it must append a line containing the ConfigMap's `MSG` value
#    to a file in an emptyDir volume mounted at `/out`.
# 4. Set `concurrencyPolicy: Forbid` and `startingDeadlineSeconds: 60`.
# 5. Then trigger a run immediately:
#
#      kubectl -n cron create job --from=cronjob/reporter reporter-manual
#
#    and check that the Job completes.
