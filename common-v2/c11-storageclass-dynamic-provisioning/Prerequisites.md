# c11 — Dynamic provisioning with a StorageClass: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `provisioning` | `LabSetUp.bash` | The claim and the Pod both live in it. The claim has to bind before the Pod can mount it, so the namespace has to exist before either does. |
| 2 | A cluster that already has a default StorageClass | the cluster itself | The task is to make a *new* class the default. The default flag is per cluster, so the class that holds it has to give it up — there is nothing to take over if no class holds it. |
| 3 | A snapshot of every StorageClass and the value of its default annotation, in `/tmp/cka-lab/c11.sc.before` | `LabSetUp.bash` | The reset restores each class's annotation exactly as it was. Without the snapshot the lab would leave `fast` as the default and the next attempt would start in a state the previous attempt created. |
| 4 | A node running the `rancher.io/local-path` provisioner | the cluster itself | The class points at that provisioner. A class that cannot provision anything is a valid API object and a poor answer: the claim will sit in `Pending` for ever. |
| 5 | A cluster with a working scheduler and a node that can run the Pod the candidate writes | the cluster itself | `WaitForFirstConsumer` binds the claim only when a pod that uses it is scheduled, so the claim cannot reach `Bound` until a pod is placed. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | StorageClass `fast` | `LabValidate.bash` |
| B | Its `provisioner` is `rancher.io/local-path` | `LabValidate.bash` |
| C | Its `volumeBindingMode` is `WaitForFirstConsumer` | `LabValidate.bash` |
| D | It carries the annotation `storageclass.kubernetes.io/is-default-class: "true"` | `LabValidate.bash` |
| E | Exactly one StorageClass in the whole cluster is marked default, and that one is `fast` | `LabValidate.bash` |
| F | PersistentVolumeClaim `data` in namespace `provisioning` | `LabValidate.bash` |
| G | The claim's phase is `Bound` | `LabValidate.bash` |
| H | The claim's `spec.storageClassName` is `fast` | `LabValidate.bash` |
| I | Pod `writer` in namespace `provisioning`, in the Running phase | `LabValidate.bash` |
| J | The Pod's template has a volume backed by claim `data`, mounted at `/data` | `LabValidate.bash` |

## Gotchas

- **`WaitForFirstConsumer` means the volume is not provisioned when the claim
  is created — it is provisioned when a pod that uses the claim is
  scheduled.** The claim sits in `Pending` until `writer` exists and is
  placed. This is the reason the claim and the Pod have to be created
  together: check the claim on its own and it looks broken; create the Pod
  and it binds within seconds.

- **The default-class flag is per cluster, not per namespace.** Making your
  class the default means the previous default has to give it up. A cluster
  with two classes annotated `storageclass.kubernetes.io/is-default-class:
  "true"` is not "a default class" — it is an ambiguity, and the admission
  plugin that stamps the default onto new claims may pick either one. The
  previous default has to be patched to `"false"` (or have the annotation
  removed) in the same breath.

- **The annotation is a string, not a boolean.** `"true"`, not `true`. A YAML
  boolean there is rejected by the API server. That is why `kubectl patch`
  needs the value quoted.

- **A claim that names no class still records the class it got.** The
  admission plugin writes the default's name into `spec.storageClassName`
  when the claim is created, so `spec.storageClassName: fast` is what proves
  the claim picked up the default rather than being told to. The class is
  frozen into the claim at that moment: changing the default afterwards does
  not re-point claims that already exist.

- **`volumeBindingMode` has only three values**, and they are spelled
  exactly: `Immediate`, `WaitForFirstConsumer`, `Immediate` is not a
  synonym for "fast". Anything else is rejected.

- **`kubectl get sc` shows the default in the DEFAULT column**, but that
  column only reflects the `storageclass.kubernetes.io/is-default-class`
  annotation. There is a second, legacy annotation
  (`beta.storageclass.kubernetes.io/is-default-class`) that older tooling
  reads; a class carrying only the legacy one looks default to some commands
  and not to others.

- **The provisioner decides whether anything can be provisioned at all.**
  Pointing the class at a provisioner that is not installed gives you a
  perfectly valid StorageClass and a claim that never binds.

## Environment requirements

- A cluster with at least one node and a working scheduler.
- A StorageClass already installed, so that there is a default to take over.
- The `rancher.io/local-path` provisioner running on a node, or whatever
  provisioner the candidate is prepared to defend.
- Registry access for the image the candidate puts in Pod `writer`.
- Permission to create and patch cluster-scoped StorageClasses, and to
  create PersistentVolumeClaims and Pods in namespace `provisioning`.
