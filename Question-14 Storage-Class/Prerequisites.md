# Q14 — Storage Class: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | A running cluster with at least one StorageClass | the playground itself | The question asks you to add a *second* class and to make it the default. With no existing class there is nothing to take the default flag away from. |
| 2 | At least one existing StorageClass that is currently the default | the playground itself | Task 3 ("ensure `local-storage` is the **only** default class") only makes sense if something else held the flag. The usual candidate is `local-path`, which ships with the local-path provisioner. |
| 3 | The `local-path` provisioner available on the nodes | the playground's CNI / local-path provisioner | The class you create points at `rancher.io/local-path`. If no node runs that provisioner, the class is valid but nothing can ever be provisioned with it. |
| 4 | A snapshot of the cluster's StorageClass and PVC state | `LabSetUp.bash`, into `/tmp/cka-lab/q14.sc.before` and `q14.pvc.before` | The reset needs to know which class was the default so it can put the flag back, and the validator needs the "before" list of claims so it can prove the task's "do not modify any existing PVCs" constraint was respected. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | StorageClass `local-storage` with provisioner `rancher.io/local-path` | `LabValidate.bash` |
| B | `volumeBindingMode: WaitForFirstConsumer` on that class | `LabValidate.bash` |
| C | `local-storage` patched to carry `storageclass.kubernetes.io/is-default-class: "true"` | `LabValidate.bash` |
| D | Every other StorageClass no longer marked default — exactly one default in the whole cluster | `LabValidate.bash` |
| E | No existing PVC or Deployment changed | `LabValidate.bash` (compares the PVC list against the snapshot) |

## Gotchas

- **A StorageClass is not the same thing as a default StorageClass.** Creating
  `local-storage` does not make it default. The flag lives in the annotation
  `storageclass.kubernetes.io/is-default-class`, and the task is explicit that it
  is created *not* default and only patched to default in a second step. A
  candidate who creates the class with the annotation already set to `"true"`
  reaches the same end state, and the validator accepts it.

- **The annotation is a string.** `"true"`, not `true`. A YAML boolean here is
  rejected by the API server, which is why `kubectl patch` needs the value
  quoted.

- **Changing the default does not retro-bind existing claims.** A PVC keeps the
  `storageClassName` it was created with; it is not re-evaluated when the
  default changes. That is exactly what the task's "do not modify any existing
  Deployments or PersistentVolumeClaims" is guarding against, and why the
  validator compares the claim list against the snapshot rather than trusting
  the outcome.

- **`volumeBindingMode: WaitForFirstConsumer` means the class binds late.** The
  volume is not provisioned when the claim is created but when a pod that uses
  the claim is scheduled. Do not expect a claim on this class to be `Bound`
  until there is a pod waiting on it.

## Environment requirements

- A cluster whose nodes run the local-path provisioner, or any provisioner you
  are willing to point the class at. The validator only checks the class
  object's fields, so the question is gradeable either way — but a class that
  can never provision anything is a poor answer to defend.
- The cluster must be reachable with `kubectl` and the current user must be
  allowed to create and patch StorageClasses (cluster-scoped).
