# c27 — A pod that will not stay up: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `broken` | `LabSetUp.bash` | The task names the namespace ("Pod `worker` in namespace `broken`"), so it has to exist before the Pod can be put in it. |
| 2 | Pod `worker` in `broken`, image `busybox:1.36` | `LabSetUp.bash` | This is the object the task is about. The task says it *is* in CrashLoopBackOff, so the Pod is pre-state and it has to be in that state when the candidate opens the task. |
| 3 | The container's command: `sh -c 'mkdir -p /data && echo ok >> /data/app.log && sleep 3600'` | `LabSetUp.bash` | The command is what does the writing. It gives the failure a concrete cause: the first thing the container does is create a directory and append to a file. |
| 4 | The container's `securityContext.readOnlyRootFilesystem: true` | `LabSetUp.bash` | This is the break. With a read-only root filesystem the `mkdir -p /data` fails with "Read-only file system", the container exits non-zero, and the kubelet restarts it with an increasing back-off. |
| 5 | The Pod's `creationTimestamp`, recorded in `/tmp/cka-lab/c27.pod.before` | `LabSetUp.bash` | A container's securityContext is immutable once the Pod exists, so the only possible fix is to delete the Pod and create it again. The recorded timestamp is how the grader proves that happened rather than the candidate having edited something else. |
| 6 | The setup waits for the crash loop to establish itself (a few seconds, up to a minute) | `LabSetUp.bash` | The first crash happens within seconds, but `CrashLoopBackOff` is a *state* the kubelet enters after repeated restarts. Waiting means the candidate meets the Pod already in the state the task describes. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | Pod `worker` in namespace `broken`, Running, with exactly 1 ready container | `LabValidate.bash` |
| B | No container sets `securityContext.readOnlyRootFilesystem: true` | `LabValidate.bash` |
| C | A Pod whose `creationTimestamp` is newer than the one recorded at setup — i.e. the Pod was re-created | `LabValidate.bash` |
| D | A container whose `restartCount` does not climb over ten seconds | `LabValidate.bash` (sampled twice, ten seconds apart) |

## Gotchas

- **A container's securityContext is immutable once the Pod exists.** Almost
  nothing in `spec` can be changed in place: `kubectl patch pod worker` on the
  `securityContext` is refused by the API server with a `Forbidden` on the
  field. The only way to change it is to **delete the Pod and create it
  again**. That is why the task tells you that you may need to re-create the
  pod, and why the grader checks the creationTimestamp: a Pod that was
  edited in place is not fixable, so a correct answer has a *new* Pod.

- **`readOnlyRootFilesystem: true` makes any write outside a mounted volume
  fail.** The container's root filesystem is mounted read-only, so `mkdir -p
  /data` cannot create the directory and `echo ok >> /data/app.log` cannot
  create the file. The fix is therefore one of two things: **mount a volume at
  `/data`** (an `emptyDir` is enough) so the write lands on a writable
  filesystem, **or allow the write** by dropping the
  `readOnlyRootFilesystem` setting. Fixing only one of the two is not enough:
  the volume alone still leaves `readOnlyRootFilesystem: true` in place, and
  the grader wants that field gone.

- **`kubectl logs worker` will not show you the error.** The container dies so
  quickly that the current container has no logs to show, and the message you
  want is from the previous instance. Use `kubectl logs worker --previous`.
  `kubectl describe pod worker` shows the same thing under "Last State:
  Terminated", with `Reason: Error` and the exit code in the events.

- **The Pod's phase stays `Running` while the container crash-loops.** The
  kubelet has not given up on the Pod, so `.status.phase` is `Running` and
  `kubectl get pod` shows `0/1`. The signal that something is wrong is in the
  container status: `state.waiting.reason: CrashLoopBackOff`, and a
  `restartCount` that keeps climbing.

- **CrashLoopBackOff is a back-off, not a crash.** The kubelet waits 10s,
  then 20s, then 40s between restarts, up to five minutes. A pod that looks
  like it "does nothing" for a while is still broken — the fix is not to wait
  longer, it is to look at the logs of the previous container.

- **A stable pod has a restartCount that stops moving.** A container that has
  been restarted five times and is now working keeps `restartCount: 5` for the
  rest of its life. The grader samples the counter twice, ten seconds apart,
  and requires the same number both times — that is what distinguishes "it
  runs" from "it will crash again in a minute".

## Environment requirements

- A cluster with at least one node and a working scheduler.
- Registry access for `busybox:1.36`, and a node with room for the Pod.
- A kubelet that restarts a failing container: the Pod needs the default
  `restartPolicy: Always` for the crash loop to happen at all. A Pod with
  `restartPolicy: Never` would go to `Error` instead, and the question would
  not be the question.
- No Pod Security Admission labels on the namespace that would reject the
  `securityContext` the setup applies — `readOnlyRootFilesystem: true` is
  allowed by the `restricted` policy, so a plain namespace is enough.
- The container needs no privilege and no host access: the failure is purely a
  filesystem permission.
