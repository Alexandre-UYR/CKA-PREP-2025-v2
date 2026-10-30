# w9 — A volume that belongs to one Pod: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `ephem` | `LabSetUp.bash` | The Pod lives here and the task names the namespace. |
| 2 | A default StorageClass with a provisioner | the cluster; `LabSetUp.bash` looks it up, and puts one in place if the cluster's default cannot dynamically provision | A generic ephemeral volume works by creating a claim and letting the default class provision it. If the default class carries `kubernetes.io/no-provisioner` — or there is no default class at all — the claim stays Pending and the Pod never starts. The setup names the class it ended up with. |
| 3 | The StorageClass the setup had to change, and the ones that were default before it | `LabSetUp.bash` | The reset has to put the cluster's own default classes back. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | Pod `eph` in namespace `ephem`, Running, container ready | `LabValidate.bash` |
| B | A volume `work` whose `ephemeral.volumeClaimTemplate` asks for 500Mi and ReadWriteOnce | `LabValidate.bash` |
| C | The volume `work` mounted at `/work` | `LabValidate.bash` |
| D | The volume is a generic ephemeral volume, not a reference to a claim you made | `LabValidate.bash` |
| E | A PersistentVolumeClaim that the Pod owns — its `ownerReferences` name the Pod, kind `Pod` | `LabValidate.bash` |
| F | That claim requests 500Mi | `LabValidate.bash` |

## Gotchas

- **A generic ephemeral volume is a Pod-local claim.** The claim is created by
  the Pod's controller when the Pod is scheduled, and it is garbage collected
  when the Pod is deleted. The Pod is its owner: that is what `ownerReferences`
  on the claim show, and it is why the claim follows the Pod around and dies
  with it. It is the modern answer to "I need a bit of scratch space that is
  not a hostPath and not a shared volume".

- **The claim does not exist until the Pod is scheduled.** The Pod controller
  creates it, and the volume only mounts once the claim is bound. A Pod that
  asks for a 500Mi ephemeral volume on a class that cannot provision it sits
  in `ContainerCreating` with the claim Pending underneath it.

- **The name of the claim is not yours to choose.** It is generated from the
  Pod name and the volume name — something like `eph-work-6d4f2` — so you
  cannot look it up by guessing. Find it by asking which claims in the
  namespace are owned by the Pod.

- **`ephemeral` is not `emptyDir`.** An `emptyDir` is a directory on the
  node, with no claim, no provisioning and no size limit. An ephemeral volume
  is a real claim: it is provisioned, it reports a size, and it has a Storage
  class behind it.

- **The volume has to be named `work`.** The task names it, and the claim's
  generated name is built from the Pod name and the volume name — so the name
  is part of the answer, not decoration.

- **Do not delete the claim by hand.** The Pod owns it; the garbage collector
  removes it when the Pod goes. Deleting it yourself leaves the Pod broken
  until the controller puts it back.

- **`ownerReferences` carry the name, the kind AND the UID.** Checking the
  name alone is not enough — a claim named after the Pod but owned by
  something else is a different thing.

## Environment requirements

- A cluster with a StorageClass that can dynamically provision volumes, and
  that class marked as the default. The setup says which one it found.
- Registry access for the image the candidate chooses, and for
  `busybox:1.36` if the setup has to check anything.
- Kubernetes 1.23 or newer. Generic ephemeral volumes were beta and enabled
  by default in 1.21, and went stable in 1.23; the older `ephemeral` resource
  — a different thing — was removed in 1.25.
