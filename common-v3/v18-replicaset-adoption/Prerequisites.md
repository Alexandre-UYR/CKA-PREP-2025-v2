# v18 — Take the pods over from their old owner: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `adopt` | `LabSetUp.bash` | The Deployment, the ReplicaSet and the pods live here, and the task names the namespace. |
| 2 | A Deployment `web` with 2 replicas, image `nginx:1.25`, labels `app=web` | `LabSetUp.bash` | The thing the task says was deleted. It is created and then deleted again so that the ReplicaSet and the pods it produced are genuine, with the labels, the hash and the ownership a real Deployment gives them. |
| 3 | A Deployment that no longer exists | `LabSetUp.bash` deletes it with `--cascade=orphan` | Without `--cascade=orphan` the Deployment's deletion would take the ReplicaSet and the pods with it and there would be nothing to adopt. Orphaning leaves them behind, which is the pre-state the task describes. |
| 4 | An orphaned ReplicaSet (`web-<pod-template-hash>`) with 2 replicas | `LabSetUp.bash` | The old owner. It still CONTROLS the two pods, and that is the trap: the new ReplicaSet cannot adopt a pod that already has a controller. |
| 5 | Two Running pods labelled `app=web`, still controlled by the old ReplicaSet | `LabSetUp.bash` | The material the candidate has to take over. They are Running, so the candidate has to adopt live pods rather than wait for them to be scheduled. |
| 6 | The original pods' names and UIDs, recorded on the namespace as the annotation `cka-lab/original-pods` | `LabSetUp.bash` | The validator uses them to tell an adopted pod from a replacement: a pod that was deleted and made again has a new UID. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | A ReplicaSet `web-adopted` in namespace `adopt` | `LabValidate.bash` |
| B | `.spec.replicas` is 2 | `LabValidate.bash` |
| C | The ReplicaSet has a non-empty selector that matches `app=web` | `LabValidate.bash` |
| D | There are 2 Running pods in the namespace | `LabValidate.bash` |
| E | Both Running pods have an `ownerReference` naming `web-adopted` | `LabValidate.bash` |
| F | That `ownerReference` says `kind: ReplicaSet` | `LabValidate.bash` |
| G | The old ReplicaSet is gone, or scaled to 0 so it owns nothing | `LabValidate.bash` |
| H | Both original pods are still the same pods (same names, same UIDs) and are owned by `web-adopted` | `LabValidate.bash` |

## Gotchas

- **A ReplicaSet adopts a pod only when the pod's labels match the
  ReplicaSet's selector AND the pod has NO controller.** A pod that is still
  controlled by another ReplicaSet is not adoptable. The old owner therefore
  has to be removed (`kubectl delete rs <old> --cascade=orphan`) or scaled to
  zero before the new ReplicaSet can take the pods over.

- **`--cascade=orphan` is what makes the transfer possible at all.** Deleting
  the old ReplicaSet the ordinary way deletes the pods it owns, and the new
  ReplicaSet then creates two fresh ones. The task says the pods must be
  adopted, and the validator checks their UIDs, so the pods have to be the
  same objects that were there before.

- **Deleting the old ReplicaSet with `--cascade=orphan` removes the pods'
  `ownerReferences`.** The pods stay Running and become orphans; the new
  ReplicaSet picks them up on its next sync, which is quick but not
  instantaneous. `kubectl get pods -o custom-columns=...` or
  `-o jsonpath='{.metadata.ownerReferences}'` shows the change.

- **The owner has to let go BEFORE the new ReplicaSet is created, or at least
  before it settles.** If the new ReplicaSet exists while the old one still
  owns the pods, the new one creates two extra pods of its own, and the
  controller then scales one set away again.

- **A Deployment and a ReplicaSet must not fight over the same pods.** This
  is why a Deployment creates a *new* ReplicaSet with a pod-template hash in
  its selector (`pod-template-hash=web-<hash>`) every time the pod template
  changes: two controllers with overlapping selectors fight over who owns
  which pod, and the result is pods being deleted and re-created for no
  reason. A hand-written ReplicaSet that takes over a Deployment's pods
  recreates the same problem, which is why the task asks for a new
  ReplicaSet whose selector is `app=web` alone.

- **The ReplicaSet's name does not matter to the adoption.** Only its
  selector does. The validator therefore looks for the old ReplicaSet by the
  `web-` prefix rather than by a hard-coded hash suffix, because the hash
  depends on the pod template.

- **The selector is a subset match, not an equality match.** A ReplicaSet
  whose selector is `app=web` matches any pod carrying `app=web`, however
  many other labels the pod has - which is why the pods it adopts also keep
  their `pod-template-hash` label.

- **An orphaned object and a broken one are not the same thing.** The
  ReplicaSet here is *orphaned*: `--cascade=orphan` removed its
  `ownerReferences`, so nothing is collecting it. A ReplicaSet that was
  merely left pointing at a Deployment that no longer exists - a dangling
  `ownerReference` - would be deleted by the garbage collector, because its
  owner is gone and nothing else keeps it alive.

## Environment requirements

- A cluster with at least one node and a working ReplicaSet controller.
- Registry access for `nginx:1.25`.
- No special components: this is plain `apps/v1` ReplicaSet and Deployment
  behaviour.
