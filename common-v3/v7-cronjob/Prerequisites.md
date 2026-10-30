# v7 — Something on a schedule: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `cron` | `LabSetUp.bash` | The CronJob, the Jobs and the material they read all live here, and the task names the namespace. |
| 2 | ConfigMap `job-config`, key `MSG` = `hello-from-the-configmap` | `LabSetUp.bash` | The value the job has to write. The CronJob must consume it through `env`/`envFrom` rather than hard-code the string, which is what makes the task about wiring things together. |
| 3 | ServiceAccount `cron-sa` | `LabSetUp.bash` | The identity the job runs as. The candidate has to point the CronJob's job template at it. |
| 4 | The cluster's **default StorageClass** | The cluster | Part of the material on offer: it is what a candidate would reach for if the report had to survive the pod. The task only needs an `emptyDir`, so this is context rather than a requirement. |
| 5 | No CronJob and no Job in the namespace | `LabSetUp.bash` recreates the namespace | The pre-state has to be exactly what the task describes — a namespace with the inputs and nothing else. The setup deletes and recreates the namespace so a Job from a previous attempt cannot pass the validation on its own. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | A CronJob `reporter` in namespace `cron` | `LabValidate.bash` |
| B | `.spec.schedule` is `*/2 * * * *` | `LabValidate.bash` |
| C | `.spec.concurrencyPolicy` is `Forbid` | `LabValidate.bash` |
| D | `.spec.startingDeadlineSeconds` is 60 | `LabValidate.bash` |
| E | The job template's container uses `busybox:1.36` | `LabValidate.bash` |
| F | The job template's pod uses the ServiceAccount `cron-sa` | `LabValidate.bash` |
| G | The container gets the ConfigMap's `MSG` value — `env` with `valueFrom.configMapKeyRef` (name `job-config`, key `MSG`), or `envFrom` with `configMapRef` | `LabValidate.bash` |
| H | The container writes to a path under `/out` | `LabValidate.bash` |
| I | A volume is mounted at `/out`, and it is an `emptyDir` | `LabValidate.bash` |
| J | A Job exists in namespace `cron` and has `status.succeeded` of at least 1 | `LabValidate.bash` |

## Gotchas

- **`concurrencyPolicy: Forbid` stops a second run starting while one is still
  going.** Without it the default is `Allow`, and a long job can overlap with
  the next scheduled one. With `Forbid`, a scheduled run that comes due while
  the previous run is still active is skipped rather than started.

- **`startingDeadlineSeconds` bounds how late a scheduled run may still
  start before it is skipped.** If the controller was down, or the cluster was
  overloaded, a run whose deadline has passed is not started at all — the
  controller gives up on it rather than firing it late. Both knobs are about
  overlapping or missed runs, and both are easy to leave out.

- **`*/2 * * * *` is every two minutes on the hour.** The CronJob controller
  creates Jobs from it, so the first Job may not appear for up to two
  minutes. That is why the task asks for a manual trigger with
  `kubectl create job --from=cronjob/reporter reporter-manual` — it makes the
  run deterministic instead of a race against the clock.

- **A CronJob is not a Job.** The schedule lives on the CronJob, the pod
  template lives at `.spec.jobTemplate.spec.template`, and the ServiceAccount
  lives at `.spec.jobTemplate.spec.template.spec.serviceAccountName`. Reading
  `.spec.template` on a CronJob finds nothing.

- **The volume has to be mounted, not just declared.** An `emptyDir` in
  `volumes` with no matching `volumeMounts` entry does not put `/out` in the
  container's filesystem.

- **`env` and `envFrom` are two ways to read the same ConfigMap.** The
  validator accepts either: `env` with `valueFrom.configMapKeyRef` naming
  `job-config` and key `MSG`, or `envFrom` with `configMapRef` naming
  `job-config`.

- **The output goes to a file, not to stdout.** `echo "$MSG" >> /out/report`
  is the shape the task asks for; the file lives in the `emptyDir` and is
  gone when the pod is.

- **The ServiceAccount has to be set on the pod template, not on the
  CronJob.** `kubectl create job --from=cronjob/...` copies the template, so
  the manual Job inherits the ServiceAccount only if the template has it.

## Environment requirements

- A cluster with a working CronJob controller (any current Kubernetes
  release) and a kube-controller-manager that can create Jobs.
- Registry access for `busybox:1.36`.
- No special components: a ConfigMap, a ServiceAccount, an `emptyDir` and the
  CronJob controller are all standard.
