# Q1 — MariaDB persistent volume: prerequisite inventory

The scenario is a small disaster recovery. Somebody deleted the Deployment *and*
the PVC, and the PersistentVolume was left behind with `reclaimPolicy: Retain`,
so the data on the node is still there. The task is to put the workload back
together **without** touching the PV, because the data lives on the PV.

## Prerequisite inventory

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `mariadb` | LabSetUp.bash | Every object in the task is "in the mariadb namespace". |
| 2 | PV `mariadb-pv`, 250Mi, `ReadWriteOnce` | LabSetUp.bash | The task says "a PersistentVolume already exists and is retained for reuse". Its capacity and access mode are the ones the PVC has to match, otherwise it will not bind. |
| 3 | `persistentVolumeReclaimPolicy: Retain` on that PV | LabSetUp.bash | `Retain` is what makes the PV (and the data on disk) survive the deletion of the PVC. With `Delete` the volume would be wiped and there would be nothing to preserve. |
| 4 | PV backed by `hostPath: /mnt/data/mariadb` | LabSetUp.bash | The database files physically live on the node's disk. The data-preservation half of the question is only real because the data outlives the PVC. |
| 5 | PV `storageClassName` set to the cluster's default StorageClass | LabSetUp.bash | The PVC you create must not name a StorageClass, so the API server defaults it. The PV has to carry the same name, or the two never match. |
| 6 | PV with a **cleared** `spec.claimRef` | LabSetUp.bash | After the PVC is deleted, a `Retain` PV goes to `Released` and keeps pointing at the dead claim. It has to be released again before a new PVC can bind to it. |
| 7 | The PVC `mariadb` and the Deployment `mariadb` deleted | LabSetUp.bash | Reproduces the accident the task describes. The deployment is created once by the setup only so the data directory gets initialised, then removed again. |
| 8 | A populated `/mnt/data/mariadb` on the node | LabSetUp.bash (starts MariaDB once, then removes the workload) | Gives "data is preserved" something to prove. The setup boots `mariadb:10.6` once against the PV so the system database is written to the volume, and only then removes the pod. |
| 9 | `~/mariadb-deploy.yaml` with `claimName: ""` | LabSetUp.bash | The task says to *edit* this file and point it at the PVC you create. The empty `claimName` is the thing you have to fix. |
| 10 | `/tmp/cka-lab/q1.pv.uid` | LabSetUp.bash | The UID of the PV as the setup left it. The grader compares it with the UID at validation time: a PV that was deleted and re-created has a different UID, and that is how "you reused the existing PV" is actually proved. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| 1 | PVC `mariadb` in namespace `mariadb`, `ReadWriteOnce`, `250Mi` | `LabValidate.bash`: "PVC mariadb exists", "PVC mariadb is Bound", "PVC mariadb requests 250Mi of storage", "PVC mariadb uses access mode ReadWriteOnce" |
| 2 | That PVC bound to the *existing* `mariadb-pv` | `LabValidate.bash`: "PVC mariadb is bound to the pre-existing PV mariadb-pv" |
| 3 | The pre-existing PV reused, not replaced | `LabValidate.bash`: "PV mariadb-pv still exists", "PV mariadb-pv still has reclaim policy Retain", "PV mariadb-pv is the SAME PV created during setup (uid unchanged...)" |
| 4 | No extra PV created | `LabValidate.bash`: "Exactly one PersistentVolume exists in the cluster" |
| 5 | `~/mariadb-deploy.yaml` filled in with `claimName: mariadb`, and applied | `LabValidate.bash`: "Deployment mariadb exists in namespace mariadb", "Deployment volume '...' points at PVC mariadb (claimName must not be empty)" |
| 6 | The deployment healthy: 1 replica, 1 ready replica, a `mariadb` image, `MYSQL_ROOT_PASSWORD` set, `/var/lib/mysql` mounted | `LabValidate.bash`: "Deployment mariadb runs 1 replica", "has 1 ready replica", "runs a mariadb image", "defines env var MYSQL_ROOT_PASSWORD", "mounts a volume at /var/lib/mysql" |
| 7 | The running pod really mounts that claim | `LabValidate.bash`: "The running pod mounts the mariadb PVC" |
| 8 | The data still there | `LabValidate.bash`: "MariaDB data directory /var/lib/mysql is not empty", "MariaDB system database directory 'mysql' is present in /var/lib/mysql" |

## Gotchas

- **Do not delete the PV.** Deleting and re-creating `mariadb-pv` is the classic
  way to "fix" a Pending PVC, and it throws the data away. The grader compares
  the PV's UID with the one captured at setup time, so a re-created PV fails even
  if the pod comes up.
- **Only one PV may exist.** The grader counts the PVs in the cluster. A second
  PV (even an empty, unused one) is a fail.
- **The PVC must not name a StorageClass.** The setup's PV carries the cluster's
  default StorageClass, so a PVC without `storageClassName` is defaulted to the
  same one and binds. Naming a different one leaves the PVC `Pending` with
  `no matching persistent volumes found`.
- **The request must be <= the PV's capacity.** The PV is exactly `250Mi`, so a
  PVC asking for more than `250Mi` will never bind.
- **A `Retain` PV that still has a stale `claimRef` is `Released`, not
  `Available`.** The setup clears it, but if you delete the PVC yourself and
  then re-create it in the same attempt, the PV goes back to `Released` and your
  new PVC stays `Pending`. `kubectl get pv mariadb-pv` shows the claim it still
  points at.
- **`claimName: ""` is not a valid reference.** If you apply the manifest without
  filling it in, the Deployment refers to a non-existent PVC and the pod never
  starts. The name goes in the `spec.template.spec.volumes[].persistentVolumeClaim`
  of the *pod template*, not at the top level of the Deployment.
- **"Running and stable" means the pod is Ready**, not merely that the
  Deployment object exists: `kubectl wait --for=condition=Available
  deployment/mariadb -n mariadb`.
- **The data lives on the node's disk**, so it survives a PVC delete but not a
  PV delete with `Retain` that points a new volume at a different path. If
  `/var/lib/mysql` comes up empty inside the pod, the pod is attached to a
  different (empty) volume, not to the original one.

## Environment requirements

- A Kubernetes cluster with at least one node and a **default StorageClass**
  (kind calls it `standard`, k3s calls it `local-path`). The setup detects it
  and puts the same name on the PV.
- A node where the kubelet can create and mount `/mnt/data/mariadb`
  (`hostPath` volumes are created by the kubelet when missing).
- The `mariadb:10.6` image pullable from a registry.
- The lab has to run on the machine that has `kubectl` configured, because
  `~/mariadb-deploy.yaml` and `/tmp/cka-lab/q1.pv.uid` are files on that
  machine.
- `~` must be writable (the setup writes `~/mariadb-deploy.yaml` there).
