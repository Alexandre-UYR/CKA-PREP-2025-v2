# v10 — The claim that will not bind: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `bind` | `LabSetUp.bash` | The task names the namespace, and both the volume and the claim live in it. |
| 2 | PersistentVolume `data-pv`: 500Mi, ReadWriteOnce, `storageClassName: fast`, `reclaimPolicy: Retain`, `hostPath` at `/tmp/data` | `LabSetUp.bash` | The volume the claim is supposed to bind. `Retain` matters: the volume survives its claim and even its deletion, so the data on it survives the exercise. |
| 3 | The volume is **Available** — no claim on it | `LabSetUp.bash` waits for `status.phase == Available` | A volume that is `Bound` or `Released` is a different fault. This one is free and waiting, so the claim is the thing that is wrong. |
| 4 | Data on the volume: `/tmp/data/data.txt` | `LabSetUp.bash` runs a short-lived pod that mounts the hostPath and writes the file | The reason the task forbids deleting the volume. A candidate who deletes the PV and re-creates it has destroyed the thing they were told to preserve, and the validator catches it through the volume's UID. |
| 5 | A StorageClass named `fast` that has no provisioner | `LabSetUp.bash` creates it if the cluster does not have it | Two jobs. It makes the PV's class name real, and it makes a claim written with `fast` impossible to provision dynamically — so the only way to bind is to the static volume. |
| 6 | The cluster's default StorageClass is not `fast`, and has no provisioner | `LabSetUp.bash` — it puts its own no-provisioner class in place when the cluster's default is not usable, and records what to restore in `/tmp/cka-lab/v10.sc.restore` | This is the fault. The claim names no class, so the API server defaults it to the cluster's default, and the default is not `fast`. The claim then waits forever for a volume of a class nobody asked for. |
| 7 | PersistentVolumeClaim `data`: 500Mi, ReadWriteOnce, **no** `storageClassName` | `LabSetUp.bash` | The claim under investigation. It agrees with the volume on the size and on the access mode; the class is the only thing that does not agree. |
| 8 | The claim is **Pending** | `LabSetUp.bash` waits for it and warns if it bound anyway | The pre-state has to actually BE broken. The setup also waits long enough for a dynamic provisioner to do the wrong thing, and warns if the claim was bound to a volume the candidate is not supposed to have. |
| 9 | The volume's UID, recorded in `/tmp/cka-lab/v10.pv.uid` | `LabSetUp.bash` | How the "do not delete the volume" instruction is graded. The UID is the volume's identity: change it and the volume was replaced, not reused. |
| 10 | The default StorageClass's name, recorded in `/tmp/cka-lab/v10.sc.before` | `LabSetUp.bash` | The name the API server defaulted the claim to. It is the answer to "which class did my claim end up with". |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | The claim `data` is Bound | `LabValidate.bash` |
| B | The claim's `.spec.volumeName` is `data-pv` — it bound to the volume that was there, not to a new one | `LabValidate.bash` |
| C | The claim's `.spec.storageClassName` is `fast` — this is the fix | `LabValidate.bash` |
| D | The volume `data-pv` still exists | `LabValidate.bash` |
| E | The volume's UID is unchanged since the setup — it was reused, not replaced | `LabValidate.bash` |
| F | The volume's `.spec.claimRef.name` is `data` | `LabValidate.bash` |

## Gotchas

- **A PersistentVolume and a PersistentVolumeClaim bind only when the access
  modes, the requested size and the StorageClass all agree.** The size and the
  access modes agree here. The StorageClass is the one people miss.

- **A claim that omits `storageClassName` is defaulted to the cluster's
  default class.** The API server fills the field in for you, and the value it
  picks is not necessarily the one you wanted. The claim then sits Pending with
  "no matching persistent volumes found" — which reads like the cluster is out
  of volumes, when in fact there is a volume right there with the right size.

- **A PV with `storageClassName: ""` matches a claim with no class at all.** A
  PV with `storageClassName: fast` matches a claim that says `fast` — and only
  that. The empty string is not "any class"; it is a class of its own.

- **`storageClassName` CAN be changed on a claim that has not yet bound.** This
  is the cheapest fix: the claim is not bound, so the field is still mutable.
  `kubectl patch pvc data -n bind -p '{"spec":{"storageClassName":"fast"}}'`
  is enough. A candidate who recreates the claim with the right class gets the
  same result — the task allows that.

- **Deleting the PV is the wrong answer even when it looks like the shortcut.**
  The volume carries `reclaimPolicy: Retain` and it holds data. Deleting the
  volume object leaves the hostPath directory on the node with the data still
  in it, but it destroys the identity of the volume: the UID changes, and a
  new volume is a new volume with a new lifecycle. The validator compares the
  UID recorded at setup time.

- **The volume's `claimRef` is set by the binder, not by you.** Once the claim
  binds, the PV's `spec.claimRef` names the claim and the volume's phase
  becomes `Bound`. Before that it is `Available`. A volume that says
  `Released` was bound to a claim that has gone.

- **Watch out for the volume being provisioned dynamically.** If the claim
  names a class that has a provisioner, the cluster may create a brand new
  volume for it — the claim binds, and the volume in front of you is still
  sitting there, unused. That is why the volume in this exercise carries a
  class with no provisioner.

## Environment requirements

- A cluster with at least one Ready node. A single-node cluster is the
  simplest: the hostPath directory and the volume are then obviously on the
  same machine.
- Registry access for `busybox:1.36` — the setup's helper pods use it, and so
  does the reset's cleanup pod.
- A `hostPath` volume is node-local. On a multi-node cluster the directory
  `/tmp/data` exists only on the node the helper pod ran on, and the setup
  pins its helper pods to one node and records that node so the reset cleans
  the same one.
