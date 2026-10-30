# c2 — Sidecar sharing an emptyDir: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `sidecar` | `LabSetUp.bash` | Every object in the task lives here, and every command is namespaced to it. |
| 2 | Deployment `app`, image `nginx:1.25`, 1 replica, labels `app=app`, **one container and no volumes** | `LabSetUp.bash` | The task says *update the EXISTING Deployment*, so there has to be one to update. It deliberately starts with no sidecar and no volumes, because both of those are what the candidate has to add. |
| 3 | A cluster with a working scheduler and a node that can run both `nginx:1.25` and `busybox:stable` | the cluster itself | Both containers have to start before the shared file can be looked at. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | A second container named `sidecar`, image `busybox:stable` | `LabValidate.bash` |
| B | The sidecar command that appends to `/var/log/app.log` | `LabValidate.bash` |
| C | A volume named `logs` of type `emptyDir` in the pod template | `LabValidate.bash` |
| D | A volumeMount named `logs` at `/var/log` in the nginx container | `LabValidate.bash` |
| E | A volumeMount named `logs` at `/var/log` in the sidecar container | `LabValidate.bash` |
| F | The Deployment rolled out, 1 ready replica | `LabValidate.bash` |
| G | `/var/log/app.log` visible inside the sidecar container | `LabValidate.bash` (live exec) |

## Gotchas

- **A Pod's containers share a lifecycle.** There is no restart policy per
  container and no "sidecar" special case in the API. If one container exits,
  the whole Pod is restarted, and the containers that were working are taken
  down with it. A sidecar is just a second container in the same Pod, so it
  has to keep running: the `while true` loop is not decoration, it is what
  keeps the Pod Running.

- **The two containers must agree on the volume name.** A `volumeMount` refers
  to a volume by *name*, not by type and not by path. If the nginx container
  mounts a volume called `logs` and the sidecar mounts one called `log`, the
  Pod will not start at all - the API server rejects the pod with
  `spec.volumes[1].name: Not found: "log"`.

- **A volume is not a mount.** Declaring `volumes:` gives the pod a place to
  put data. Nothing is shared until *both* containers list a `volumeMount` for
  it. A single container mounting the emptyDir shares it with nobody.

- **A mount path is a directory, and it hides what was there.** Mounting over
  `/var/log` in the nginx container puts the emptyDir's contents at that path
  and hides the image's original `/var/log` directory. That is what the task
  asks for, and it is why the emptyDir has to be mounted at the same path in
  both containers.

- **`emptyDir` is scoped to the Pod, not to the Deployment.** It is created
  with the pod and destroyed with it. A new ReplicaSet means new pods, means
  new emptyDirs, means the log file starts again from empty. Do not expect
  the file to survive a rollout.

- **Editing a Deployment is a rollout, not an edit.** Changing the pod
  template creates a new ReplicaSet and the old pods are scaled down. The
  candidate has to wait for the new pod to become ready before the live check
  can pass.

- **`kubectl apply` on a Deployment that already exists is a merge, not a
  replace.** `spec.selector` is immutable, and the container list is merged by
  container name - so adding a container called `sidecar` works, but adding a
  second container also called `nginx` does not.

## Environment requirements

- A cluster with at least one node and a working scheduler.
- Registry access for `nginx:1.25` and `busybox:stable`.
- Nothing else. The Pod needs no Service, no storage class and no special CNI
  - an `emptyDir` needs no provisioner.
