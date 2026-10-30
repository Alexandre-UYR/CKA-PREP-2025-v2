# c25 — Scale, update, roll back: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `release` | `LabSetUp.bash` | The task works on the Deployment in it. The namespace has to exist before the Deployment can be created in it. |
| 2 | Deployment `api`: 2 replicas, image `nginx:1.25`, labels `app: api` | `LabSetUp.bash` | This is the object the task operates on. It starts healthy, so that the only thing that can go wrong is what the candidate does. |
| 3 | The Deployment is available - 2 ready replicas - before the task starts | `LabSetUp.bash` | The task ends with "wait for the rollout to finish" and "2 ready replicas". A Deployment that was already broken would make the result meaningless. |
| 4 | The Deployment already has a rollout history: revision 1 (an earlier one) and revision 2 (the current one) | `LabSetUp.bash` | `kubectl rollout undo` restores the *previous* revision. A Deployment that has only ever been applied once has exactly one revision and there is nothing to roll back to. The second revision is created by an annotation on the pod template, so it needs no second image. |
| 5 | The Deployment's UID, recorded in `/tmp/cka-lab/c25.uid` | `LabSetUp.bash` | The task says "do not delete and re-create the Deployment". The UID is the only way to tell an edit from a re-creation: `kubectl scale`, `kubectl set image` and `kubectl rollout undo` all patch the object and leave its UID alone, while deleting and re-applying it changes the UID. |
| 6 | A cluster with a node that can pull `nginx:1.25` and `nginx:1.26` | the cluster itself | Both the starting image and the updated one have to be pullable, or the rollout never completes and the "wait for the rollout to finish" step cannot be demonstrated. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | The Deployment still exists, with the same UID as before the task | `LabValidate.bash` |
| B | `.spec.replicas` is 2 - the scale back | `LabValidate.bash` |
| C | `.status.readyReplicas` is 2 | `LabValidate.bash` |
| D | The container image is `nginx:1.25` again - the rollback undid the update | `LabValidate.bash` |
| E | The revision history has at least 3 entries | `LabValidate.bash` |

## Gotchas

- **`kubectl rollout undo` restores the previous REVISION, so it only undoes
  the last change.** The scale and the image update are two separate changes,
  and the rollback only reaches the last one. The order in the task is scale
  first, image second: after the image update, one `undo` takes the
  Deployment back to the image it had before the update - `nginx:1.25` - and
  the replica count is still 5. That is why the task asks for the scale back
  to 2 explicitly. A rollback restores the *pod template*, not the whole
  Deployment.

- **`kubectl rollout undo` without `--to-revision` goes back one revision.**
  `kubectl rollout undo deploy/api -n release` undoes the newest revision.
  `--to-revision=N` goes back to a named one, and `--to-revision=0` is the
  same as no flag at all.

- **A rollback creates a NEW revision rather than deleting the bad one.** The
  ReplicaSet for the bad image is scaled down to zero but stays in the
  history, and the rollback gets a revision of its own. This is why the
  history grows: it is a log, not a stack. `kubectl rollout history
  deploy/api -n release` lists every revision the Deployment has ever been
  at, and the number of entries only ever goes up.

- **Scaling does not create a revision.** A Deployment's revision counts
  changes to the *pod template* - the image, the labels, the environment, the
  annotations. `kubectl scale` changes `spec.replicas` and nothing else, so
  it leaves the revision history alone. That is the second reason the scale
  has to be undone by hand.

- **`kubectl set image` starts a rollout that has to be waited for.**
  `kubectl set image deploy/api api=nginx:1.26` returns as soon as the
  request is accepted; the old pods are still running and the new ones are
  still pulling. `kubectl rollout status deploy/api -n release` waits for the
  new ReplicaSet to come up, and `kubectl rollout undo` issued too early
  rolls back a rollout that has not finished.

- **The container is named `api`, so the image is set with
  `api=nginx:1.26`.** `kubectl set image` takes `CONTAINER=IMAGE`; giving it
  the wrong container name errors out rather than doing nothing.

- **Deleting and re-applying the Deployment would satisfy every other check
  and still be the wrong answer.** A re-created Deployment comes back with 2
  replicas, `nginx:1.25` and 2 ready replicas - but a new UID, and a
  revision history of its own. That is why the UID is recorded at setup time
  and compared at validation time.

- **`.spec.replicas` and `.status.readyReplicas` are two different numbers.**
  The first is what was asked for, the second is what has actually come up.
  The grader checks both: a Deployment that was scaled to 2 while the old
  pods are still terminating has `.spec.replicas` 2 and fewer ready replicas
  for a few seconds.

## Environment requirements

- A cluster with at least one node and a working scheduler.
- Registry access for `nginx:1.25` and `nginx:1.26`.
- Permission to patch Deployments in namespace `release`, and to scale them.
- Enough room on the node for 5 replicas of nginx while the rollout is in
  flight - the scale to 5 happens before the update, and the old and the new
  pods coexist briefly.
- No `kubectl rollout undo` plugin or extra tooling: everything the task
  needs is in kubectl.
