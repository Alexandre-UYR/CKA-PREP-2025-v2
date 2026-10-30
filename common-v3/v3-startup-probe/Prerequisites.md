# v3 — The app that is killed before it starts: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `probe` | `LabSetUp.bash` | The Deployment and its pod live here, and the task names the namespace. |
| 2 | Deployment `slow`, 1 replica, labels `app=slow` | `LabSetUp.bash` | The workload under investigation. It exists so the candidate can fix the pod template in place rather than build something new. |
| 3 | Container `app`, image `busybox:1.36`, command `sleep 60; sleep 3600` | `LabSetUp.bash` | The application itself. It takes 60 seconds to become useful, then stays up. The command is fixed by the task: the candidate fixes the probes, not the app. |
| 4 | A liveness probe: `httpGet` on `/health` port `8080`, `initialDelaySeconds: 5`, `periodSeconds: 5`, `failureThreshold: 3` | `LabSetUp.bash` | The cause. Nothing listens on 8080 — the container is only sleeping — so the probe fails every time and the kubelet kills the container about 15 seconds in, well before the 60-second start-up finishes. |
| 5 | No startup probe | `LabSetUp.bash` | The missing piece. Without one, the liveness probe is evaluated from the first second of the container's life. |
| 6 | The container has already been restarted at least once | `LabSetUp.bash` waits for it | The pre-state has to BE the broken state. The setup polls the restart count and warns if the kubelet has not killed the container yet. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | A `startupProbe` on the container, either `exec` or `httpGet` | `LabValidate.bash` |
| B | The startup probe's budget — `failureThreshold x periodSeconds` — is at least 60 seconds | `LabValidate.bash` |
| C | The app still has its 60-second start-up; it was not simply shortened to make the probe pass | `LabValidate.bash` |
| D | The pod is Running | `LabValidate.bash` |
| E | The container is Ready | `LabValidate.bash` |
| F | The restart count is stable — sampled twice, 25 seconds apart | `LabValidate.bash` |

## Gotchas

- **A startup probe gates the liveness and readiness probes.** While the
  startup probe has not succeeded, the liveness probe is not evaluated at
  all. That is the whole mechanism: the liveness probe is not "slowed down",
  it is suspended.

- **The arithmetic matters.** The startup probe is allowed
  `failureThreshold x periodSeconds` to succeed, and the kubelet restarts the
  container if it has not succeeded within that budget. With the defaults
  (`failureThreshold: 3`, `periodSeconds: 10`) the budget is 30 seconds —
  still not enough. It has to be at least 60. A budget of exactly 60 is
  cutting it fine, because the probe's first run is not instant; give it
  some slack (`12 x 5`, or `15 x 5`).

- **`initialDelaySeconds` does not count towards the budget.** It only delays
  the first attempt. The budget alone has to cover the 60 seconds.

- **The liveness probe cannot be left as it is.** There is no server on 8080
  — the container is `sleep 60; sleep 3600` — so the moment the startup probe
  succeeds, the liveness probe starts failing again and kills the container.
  The candidate has to make the liveness probe harmless: remove it, replace
  it with an `exec` probe that reflects the application's real state, or give
  it a budget that will not expire in practice. The validator's restart-count
  check is what catches a candidate who only added a startup probe and left
  the liveness probe in place.

- **The restart-count window is 25 seconds, not 10.** The old liveness probe
  kills the container about 15 seconds after it starts (5 second initial
  delay, then three failures 5 seconds apart). A 10 second sample can easily
  fall between two kills and report a stable count for an app that is still
  being killed. 25 seconds cannot miss it.

- **A startup probe that succeeds instantly defeats the purpose.** The pod
  would report Ready while the application is still starting up. The
  application has to publish something the probe can see — a marker file, a
  PID, a port that is actually open — and the probe has to wait for it.

- **The container's command must not be watered down.** Removing
  `sleep 60` makes every probe pass and every budget sufficient, and solves
  nothing. The validator checks that the 60-second start-up is still there.

## Environment requirements

- A cluster with at least one node, and `kubectl` in the current context.
- Registry access for `busybox:1.36`.
- The kubelet has to be able to probe the pod over the network for the
  `httpGet` liveness probe to fail the way the task describes — that is the
  default on a local cluster and on most managed ones.
- No special components: this is plain kubelet probe behaviour.
