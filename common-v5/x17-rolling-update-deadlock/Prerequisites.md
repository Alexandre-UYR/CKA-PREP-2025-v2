# x17 — The rollout that can never move: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `rollout` | `LabSetUp.bash` | The Deployment lives here, and the task names the namespace. |
| 2 | Deployment `web` — 3 replicas, `nginx:1.25`, labels `app=web` | `LabSetUp.bash` | The workload. Its three pods are healthy and Ready, which is what makes the failure hard to see: `kubectl get deploy` says `3/3`. |
| 3 | The pod template changed to `nginx:1.26` | `LabSetUp.bash` | The Deployment wants to roll out a new version. The template says 1.26 while every running pod is on 1.25, so there is something to be stuck about. |
| 4 | The Deployment is **paused** (`spec.paused: true`) | `LabSetUp.bash` | The failure. A paused Deployment does not roll out a changed pod template: the controller synchronises the status and nothing else, so no new ReplicaSet is ever created. |
| 5 | The Deployment's UID and the original image recorded | `LabSetUp.bash`, into `/tmp/cka-lab/x17.deploy.uid` and `/tmp/cka-lab/x17.image` | The task forbids deleting the Deployment, so the grader compares the UID at validate time with the one recorded here. |
| 6 | The pre-state to actually be stuck | `LabSetUp.bash` checks the paused flag, the template image, `updatedReplicas` and the running images, and warns if they are not what it expects | The pre-state has to BE the broken state. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | The Deployment still there, with the UID recorded at setup — fixed in place | `LabValidate.bash` |
| B | Its strategy still `RollingUpdate`, and the strategy allows progress | `LabValidate.bash` |
| C | The pod template still asks for `nginx:1.26` | `LabValidate.bash` |
| D | The Deployment no longer paused | `LabValidate.bash` |
| E | `.status.updatedReplicas` equal to `.spec.replicas` (3) | `LabValidate.bash` |
| F | `.status.readyReplicas` equal to 3 | `LabValidate.bash` |
| G | `.status.observedGeneration` equal to `.metadata.generation` — the rollout has actually been processed | `LabValidate.bash` |
| H | No pod of the Deployment left on `nginx:1.25` | `LabValidate.bash` |

## Gotchas

- **`maxSurge` is how many pods MAY be created above the desired count and
  `maxUnavailable` is how many may be unavailable.** With BOTH at zero the
  controller is not allowed to create the new pod and not allowed to delete
  the old one, so the rollout is deadlocked — the Deployment waits forever for
  a progress that the strategy forbids. A rolling update needs one of the two
  to be non-zero.

- **But you cannot build that deadlock through the API.** The API server
  refuses a Deployment whose rolling update has both values at zero:

  ```
  spec.strategy.rollingUpdate.maxUnavailable: Invalid value: 0: may not be 0 when `maxSurge` is 0
  ```

  So if the strategy looks innocent, look elsewhere — and in this exercise the
  strategy *is* innocent: it is at the default `25%`/`25%`.

- **A paused Deployment looks healthy.** `kubectl get deploy` reports
  `3/3` ready and `0` up to date, and the pods are all Running. Nothing in
  `kubectl get pods` looks wrong. The reason is in the Deployment's
  conditions (`Progressing: False, reason: DeploymentPaused`) and in
  `Paused: true` in `kubectl describe deploy`.

- **`kubectl rollout resume`, or patch `spec.paused` to false.** Both work;
  the first is the shorter way round. `kubectl rollout undo` is not what you
  want here — it rolls back to the previous template instead.

- **Deleting the pods does not help.** The pods belong to a ReplicaSet whose
  template is still `nginx:1.25`, so the ReplicaSet recreates them on the old
  image. The change that has to happen is the one on the Deployment.

- **Deleting and re-creating the Deployment is forbidden.** It would also
  throw away the whole history of the object. The UID check catches it.

- **`observedGeneration` is what tells you the rollout was processed.**
  `.metadata.generation` counts the changes to the spec; the controller copies
  it into `.status.observedGeneration` once it has acted on them. If the two
  differ, the controller has not seen the last edit yet.

## Environment requirements

- A cluster with at least one node, and registry access for `nginx:1.25` and
  `nginx:1.26`.
- No special components. This is plain Deployment and ReplicaSet behaviour.
