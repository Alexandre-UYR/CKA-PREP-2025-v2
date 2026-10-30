# v1 — A log nobody can read: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `sidecar` | `LabSetUp.bash` | The Deployment and its pod live here, and the task names the namespace. |
| 2 | Deployment `web`, 1 replica, labels `app=web` | `LabSetUp.bash` | The workload the candidate has to modify in place. It exists so the app container and its command are already there to work from. |
| 3 | Container `app`, image `nginx:1.25` | `LabSetUp.bash` | The image is irrelevant to the fix — what matters is that the container has a writable filesystem of its own. The busybox-like `sh` inside it is what writes the log. |
| 4 | The app writes to `/var/log/app.log` in a loop | `LabSetUp.bash` — `while true; do echo ... >> /var/log/app.log; sleep 5; done` | The log has to actually exist, and it has to keep growing, or "the log is shared" is not observable. The path is fixed by the task: the candidate must not move it. |
| 5 | No volume mounted at `/var/log` — and no volume at all | `LabSetUp.bash` | This is the fault. `/var/log/app.log` is created inside the container's own writable layer, so it is invisible to any other container and is wiped every time the container restarts. |
| 6 | No sidecar container | `LabSetUp.bash` | There is nothing to read the log. The candidate has to add a container, not just a volume. |
| 7 | The app has already written at least one log line | `LabSetUp.bash` waits for it | The pre-state has to BE the state the task describes. The setup polls the file from inside the container and warns if nothing has been written yet. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | A second container named `logreader`, image `busybox:1.36` | `LabValidate.bash` |
| B | The `logreader` command tails `/var/log/app.log` | `LabValidate.bash` |
| C | A volume named `shared-logs` of type `emptyDir` | `LabValidate.bash` |
| D | The app container mounts `shared-logs` at `/var/log` | `LabValidate.bash` |
| E | The `logreader` container mounts `shared-logs` at `/var/log` | `LabValidate.bash` |
| F | The app container still writes to `/var/log/app.log` | `LabValidate.bash` |
| G | The Deployment has exactly two containers and one ready replica | `LabValidate.bash` |
| H | `kubectl -n sidecar exec deploy/web -c logreader -- cat /var/log/app.log` prints the app's log lines | `LabValidate.bash` |

## Gotchas

- **The check that catches a half-finished answer is H.** Adding the volume to
  the pod but mounting it only in the sidecar — or mounting it in both
  containers at the wrong path — leaves the app writing into its own layer.
  The spec will look perfect; the log will still be empty. That is why the
  validator reads the file from inside the sidecar instead of trusting the
  YAML. Run it yourself:
  `kubectl -n sidecar exec deploy/web -c logreader -- cat /var/log/app.log`

- **`emptyDir` is per-pod, not per-container.** Two containers in the same pod
  see the same `emptyDir`; two pods would not. This question is about one pod
  with two containers, so an `emptyDir` is the right volume type and a
  `hostPath` or a PVC is not needed.

- **Mounting at `/var/log` shadows the image's own `/var/log`.** That is what
  the task asks for, and it is safe here because the container's command is
  overridden — the nginx entrypoint is not running. Nothing in this image
  needs the original `/var/log/nginx` directory.

- **A sidecar that dies takes the pod down.** If `logreader` runs
  `tail -f /var/log/app.log` and the file does not exist yet when the sidecar
  starts, `tail` exits and the container is restarted. Wait for the file to
  exist, or use `tail -F`, so the sidecar stays up. The validator requires one
  ready replica, which is what catches this.

- **The app's command must not change.** The task says the app keeps writing
  to the same path. A candidate who rewrites the app container's command to
  write somewhere else has moved the problem rather than solved it, and the
  validator fails the "still writes to /var/log/app.log" check.

- **Exactly two containers.** The Deployment starts with one. Adding a second
  one that is not the sidecar — a debugging helper, a second tail — fails the
  container-count check.

## Environment requirements

- A cluster with at least one node, and `kubectl` in the current context.
- Registry access for `nginx:1.25` and `busybox:1.36`.
- `kubectl exec` has to work into a container in the pod, which it does by
  default on a local cluster and on most managed ones.
- No special components: this is plain pod and volume plumbing.
