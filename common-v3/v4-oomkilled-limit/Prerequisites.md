# v4 — The pod that keeps being killed: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `oom` | `LabSetUp.bash` | The Deployment and its pod live here, and the task names the namespace. |
| 2 | Deployment `greedy`, 1 replica, labels `app=greedy` | `LabSetUp.bash` | The workload under investigation. It exists so the candidate can fix it in place rather than build something new. |
| 3 | A container that allocates ~100MB | `LabSetUp.bash` — `x=$(yes \| head -c 100000000)` | The cause of the failure. The command substitution holds the whole 100MB in the shell's memory, which is more than the cgroup allows. |
| 4 | A memory **request** of 16Mi and a memory **limit** of 32Mi | `LabSetUp.bash` | The limit is what kills the container. The request is what the scheduler reserves. Both are part of the puzzle: the candidate has to reason about which of them to change. |
| 5 | The container already OOMKilled at least once | `LabSetUp.bash` waits for it | The pre-state has to actually BE the broken state. The setup polls for `lastState.terminated.reason == OOMKilled` and warns if it has not happened yet. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | The container still has a memory limit — it was not simply deleted | `LabValidate.bash` |
| B | The limit is at least the request | `LabValidate.bash` |
| C | The pod is Running and the container is ready | `LabValidate.bash` |
| D | The container's last termination is no longer `OOMKilled` | `LabValidate.bash` |
| E | The restart count has stopped climbing — sampled twice, ten seconds apart | `LabValidate.bash` |

## Gotchas

- **`CrashLoopBackOff` is a symptom, not a cause.** Every crash-looping pod
  reports it. The cause is in `kubectl describe pod` (the "Last State: Terminated,
  Reason: OOMKilled" block) or in `.status.containerStatuses[0].lastState`.
  A candidate who reads only the phase has not diagnosed anything.

- **The restart count is the real test.** A pod can be `Running` at the instant
  you look at it and be killed two seconds later. The validator samples
  `restartCount` twice, ten seconds apart, and requires it to be unchanged —
  that is what "it stays up" means, as opposed to "it is up right now".

- **The limit cannot be removed.** The task says so, and it is right: an
  unlimited container can take the node down with it. The fix is a limit the
  container can live within, not no limit.

- **Raising the limit is not always the whole answer.** The request also
  matters: the request is what the scheduler reserves and what a QoS class is
  computed from. A candidate who raises the limit to a huge number but leaves a
  16Mi request has produced a `Burstable` pod that the scheduler may still
  place badly.

- **A pod that was OOMKilled keeps its `lastState` even after it recovers.**
  The validator therefore checks the live behaviour (restart count stable) as
  well as the history, so a candidate cannot pass by leaving a stale OOMKilled
  record behind.

## Environment requirements

- A cluster with at least one node and enough memory for the container to
  start allocating before it is killed. The limit is 32Mi, so any node works.
- Registry access for `busybox:1.36`.
- No special components: this is a plain cgroup and kubelet behaviour.
