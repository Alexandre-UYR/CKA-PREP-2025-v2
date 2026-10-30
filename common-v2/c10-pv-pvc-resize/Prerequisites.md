# c10 — Expand a PersistentVolumeClaim: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `resize` | `LabSetUp.bash` | The task puts the claim in this namespace. The volume itself is cluster-scoped, the claim is not. |
| 2 | StorageClass `expandable` with `allowVolumeExpansion: true` | `LabSetUp.bash` | A claim can only be expanded if the StorageClass it references allows expansion. Without this class there is nothing in the cluster that a claim could be expanded against, and the API server rejects the resize with `only dynamically provisioned pvc can be resized and the storageclass that provisions the pvc must support resize`. |
| 3 | The same class has `provisioner: rancher.io/local-path` | `LabSetUp.bash` | The provisioner is what names the class as one of this cluster's local-storage classes. The claim is bound to a static volume, so the provisioner is never asked to do anything, but the class has to look like the ones the cluster already uses. |
| 4 | The cluster's **default** StorageClass, whatever it is called, does **not** allow expansion | the cluster, deliberately left alone | This is the trap. A claim that leaves out `storageClassName` is defaulted to the cluster's default class, and if that class does not allow expansion the resize is refused by the API server. The claim has to name `expandable` explicitly. The setup creates `expandable` and does not touch the default class. |
| 5 | A node that can run a `hostPath` volume | the cluster itself | The volume's data lives in `/tmp/expand-data` on a node, so at least one node has to be available to run a Pod that mounts it. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | PersistentVolume `expand-pv`: 100Mi, `ReadWriteOnce`, `storageClassName: expandable`, a `hostPath` at `/tmp/expand-data` | `LabValidate.bash` |
| B | PersistentVolumeClaim `expand-pvc` in namespace `resize`: 10Mi, `ReadWriteOnce`, `storageClassName: expandable` | `LabValidate.bash` |
| C | The claim is `Bound`, and `spec.volumeName` is `expand-pv` | `LabValidate.bash` |
| D | The claim requests `70Mi` after the expansion | `LabValidate.bash` |
| E | The claim reports a capacity that covers the expanded request | `LabValidate.bash` |
| F | StorageClass `expandable` still has `allowVolumeExpansion: true` | `LabValidate.bash` |

## What the API server does and does not let you do

The claim's `spec.resources.requests.storage` is only ever changed by a
client. The API server does not raise it on its own, and it validates the
change on the way in:

- **Only a bound claim can be expanded.** A claim that is still `Pending` is
  rejected with `Only bound persistent volume claims can be expanded`. Wait for
  `Bound` before you resize.
- **The claim has to name a StorageClass, and that class has to allow
  expansion.** The check is made against the class the claim names - which,
  for a claim that omits `storageClassName`, is the cluster's default class.
  This is the trap: a claim on the default class cannot be expanded, and the
  API server refuses the new size even though the size itself is perfectly
  reasonable.
- **A claim can grow, never shrink.** `field can not be less than previous
  value`.

So the request of 70Mi surviving in the spec is the proof that the expansion
was accepted: nothing but the API server can write that field, and it only
lets the value through when the class the claim names allows expansion.

## The two capacities

The volume keeps `spec.capacity.storage: 100Mi`. The volume's own capacity
never changes, because `hostPath` has no resizing support: there is no
backend that could grow the directory. The claim is the object that is
enlarged, and it reports the capacity of the volume it is bound to - which is
100Mi, comfortably covering the 70Mi it now asks for. On a driver that does
support resizing, the claim's reported capacity would end up exactly at the
new size.

The validator therefore checks that the claim *reports* a capacity of at
least the size it requests, rather than a capacity of exactly 70Mi.

## Gotchas

- **`storageClassName` on the claim is not optional here.** Leave it out and
  the claim lands on the default class, and the resize is refused. Name it:
  `storageClassName: expandable`.

- **The volume and the claim have to agree on the class.** A volume on one
  class does not bind to a claim on another, so the claim stays `Pending` and
  the resize is refused with `Only bound persistent volume claims can be
  expanded`.

- **A static volume needs `volumeName` on the claim.** With
  `spec.volumeName: expand-pv` the claim binds to that volume directly. Leave
  it out and the class's provisioner is asked for a volume instead, which
  creates a *different* volume and leaves `expand-pv` sitting there
  `Available`.

- **The claim's request can be smaller than the volume's capacity.** 10Mi
  against a 100Mi volume is fine; the volume is simply bigger than the claim
  asked for.

- **`kubectl patch` is the usual way to resize.** `kubectl edit pvc` works
  too. What does not work is editing the status: the size that matters is in
  the spec.

- **The `hostPath` directory is on the node.** It is created when the volume
  is first used and it survives the deletion of the volume and of the
  namespace, so the reset cleans it through a pod on the node.

- **The volume is cluster-scoped.** Deleting the namespace does not delete it,
  and the reset deletes it explicitly.

## Environment requirements

- A cluster with at least one node and a working storage setup.
- Registry access for `busybox:1.36`, which the reset uses to clean the
  `hostPath` directory from the node.
- No CSI driver needed: the volume is a plain `hostPath`, so no external
  provisioner or resizer has to be installed.
