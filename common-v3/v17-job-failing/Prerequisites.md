# v17 — The Job that will never finish: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `jobs` | `LabSetUp.bash` | The Job and its pods live here, and the task names the namespace. |
| 2 | Job `import` | `LabSetUp.bash` | The workload under investigation. It exists so the candidate has to diagnose a broken Job rather than build a working one. |
| 3 | `completions: 3`, `parallelism: 1`, `backoffLimit: 2` | `LabSetUp.bash` | The three knobs the task keeps. `completions` is how many pods must **succeed**, `parallelism` is how many run at once, `backoffLimit` is how many failures are tolerated before the Job gives up. |
| 4 | A container that runs `sh -c 'echo "starting"; exit 1'` | `LabSetUp.bash` | The cause of the failure. The container starts and exits non-zero immediately, so the pod fails before it has done any work. |
| 5 | `restartPolicy: Never` | `LabSetUp.bash` | The default for a Job, and the reason the failure is terminal. A Job's pods are deliberately **never restarted**: a failed pod stays failed, and the Job creates a *new* pod instead. |
| 6 | The Job has already exhausted its retries and carries the `Failed` condition | `LabSetUp.bash` waits for it | The pre-state has to actually BE the broken state. The setup polls for the `Failed` condition and warns if it has not appeared yet. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | A Job `import` in namespace `jobs` | `LabValidate.bash` |
| B | `.spec.completions` is still 3 | `LabValidate.bash` |
| C | `.spec.backoffLimit` is 2 or lower | `LabValidate.bash` |
| D | The container no longer exits 1 straight away | `LabValidate.bash` |
| E | `.status.succeeded` is 3 | `LabValidate.bash` |
| F | The Job's `Complete` condition is `True` | `LabValidate.bash` |
| G | The Job has three pods of its own, and all three are `Succeeded` | `LabValidate.bash` |

## Gotchas

- **A Job's pod template is immutable.** `kubectl edit job import` fails with
  `spec.template: Forbidden: updates to job spec for fields other than
  'suspend' are forbidden`. The only fix is to delete the Job and create it
  again — which is why the task says to keep the same name, the same
  completion count, and the same backoffLimit.

- **A Job's pods are never restarted.** A pod that exits non-zero goes to the
  `Failed` phase and stays there. The Job controller responds by creating a
  *new* pod, up to `backoffLimit` times. `restartPolicy: Always` is not even
  allowed on a Job: a Job that restarts its container forever would never
  count a completion.

- **`backoffLimit` is how many failures are tolerated, not how many attempts
  are made.** With `backoffLimit: 2` the Job makes three pod attempts; once
  the third one fails, `status.failed` (3) exceeds `backoffLimit` (2) and the
  Job takes the `Failed` condition. Raising `backoffLimit` would only make
  the Job keep failing for longer, which is why the task forbids it.

- **`completions` counts pods that SUCCEED.** It is not a deadline and not a
  restart count. `parallelism` is how many of those pods may run at the same
  time. `completions: 3` with `parallelism: 1` means three pods, one after
  another, all of which have to exit zero.

- **The reason is in the pod, not in the Job.** `kubectl get job` shows
  `FAILED` and a count. The cause is in `kubectl -n jobs logs <pod>` (the
  container prints `starting` and then stops) and in the pod's exit code
  (`kubectl describe pod` shows `Exit Code: 1`). A candidate who reads only
  `kubectl get job` has learned nothing about the cause.

- **Between two pod attempts the Job waits.** The controller backs off
  exponentially (10s, then 20s, and so on), so a Job that is going to fail
  takes half a minute to fail. `kubectl get job import -w` shows the pods
  appearing one at a time.

- **Deleting the Job with `--cascade=orphan` leaves the failed pods behind.**
  They keep the label `job-name=import`, so `kubectl get pods -l job-name=import`
  still shows them after the fix. The validator only looks at the pods the
  current Job owns, but a tidy answer deletes the old pods too.

## Environment requirements

- A cluster with at least one node and a working Job controller.
- Registry access for `busybox:1.36`.
- No special components: this is plain `batch/v1` Job behaviour.
