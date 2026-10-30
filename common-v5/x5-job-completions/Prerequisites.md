# x5 — Ten of them, five at a time: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `jobs` | `LabSetUp.bash` | The task names the namespace, and the Job and its pods live there. The namespace is recreated on every run, so a Job the candidate already replaced cannot answer the validation on its own. |
| 2 | Job `import` with the **default** settings — `completions: 1`, `parallelism: 1`, `backoffLimit: 6` | `LabSetUp.bash` | The starting point. A Job with no `completions` runs its work once, one pod at a time. |
| 3 | The Job's container, `busybox:1.36` running `sh -c 'sleep 5'` | `LabSetUp.bash` | The work itself, and it is short enough that ten completions take a handful of seconds. The task says the replacement runs the same container, so the container is not part of the puzzle. |
| 4 | `restartPolicy: Never` on the pod template | `LabSetUp.bash` | A Job's pods must not be restarted in place — that is what `restartPolicy: Never` means, and it is required by the Job API. |
| 5 | The Job to have actually completed once | `LabSetUp.bash` polls for it | The pre-state has to BE the state the task describes: a Job that ran once with the default settings. The setup waits for one successful completion and warns if it never arrived. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | A Job `import` in namespace `jobs` | `LabValidate.bash` |
| B | `.spec.completions` is 10 | `LabValidate.bash` |
| C | `.spec.parallelism` is 5 | `LabValidate.bash` |
| D | `.spec.backoffLimit` is set, and between 1 and 6 | `LabValidate.bash` |
| E | `.status.succeeded` is 10 | `LabValidate.bash` |
| F | The Job's `Complete` condition is `True` | `LabValidate.bash` |
| G | The container still runs the same image | `LabValidate.bash` |

## Gotchas

- **`completions` is how many pods must SUCCEED before the Job is done.**
  It is not the number of pods that get created, and it is not the number of
  attempts. Ten completions means ten pods that ran and exited 0.

- **`parallelism` is how many run at the same time.** With `parallelism: 5`
  and `completions: 10`, the Job makes two waves of five pods. The two
  numbers are independent of each other; nothing derives one from the other.

- **`backoffLimit` is how many failures are tolerated before the Job gives
  up** and takes the `Failed` condition. With the default of 6, a Job makes
  seven attempts before it gives up. Setting it to 0 means a single failure
  ends the Job — which is why the task asks for it to be set rather than left
  at zero.

- **A Job's pod template is immutable.** `kubectl edit job import` refuses
  to change the template:
  `error: updates to job spec for fields other than 'suspend' are forbidden`.
  The Job has to be **deleted and re-created** — with the same name, and with
  the same container. That is the whole shape of the answer.

- **The Job's old pods are not the new Job's pods.** When the Job is deleted,
  its pods go with it, and the new Job creates ten new ones. A `kubectl get
  pods -l job-name=import` afterwards shows the new Job's pods only.

- **A Job that has already completed does not start again by itself.** Once
  it takes the `Complete` condition it is done; changing `completions` on a
  completed Job does not resurrect it on its own. Replacing the Job is the
  reliable route.

- **`completions` and `parallelism` are editable, the template is not.** It is
  possible to scale a Job by patching those two numbers, but the pod template
  stays whatever it was, and a Job that has already finished will not
  necessarily pick the work up again. Delete and re-create is the answer the
  task is looking for.

## Environment requirements

- A cluster with at least one node, and registry access for `busybox:1.36`.
- No special components. This is the Job controller behaving exactly as
  documented.
