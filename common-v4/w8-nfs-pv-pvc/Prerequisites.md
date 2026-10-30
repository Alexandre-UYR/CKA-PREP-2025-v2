# w8 — A volume with something already on it: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `web` | `LabSetUp.bash` | The claim, the Deployment and the Service all live here and the task names the namespace. |
| 2 | PersistentVolume `pvvol` — 1Gi, ReadWriteMany, reclaim policy `Retain`, `storageClassName: ""`, `hostPath` `/opt/shared`, pinned to one node | `LabSetUp.bash` | The volume the claim has to bind to. It carries data, so it must survive the exercise, and it has to be the one the claim binds to. |
| 3 | The file `/opt/shared/index.html`, holding the text `shared content served from the volume` | `LabSetUp.bash` | The thing that has to be served. It is written by a short-lived pod that mounts the same hostPath, because a hostPath resolves on the NODE — the directory has to be created on the node, not on the machine running kubectl. |
| 4 | The PV's UID, recorded at setup time | `LabSetUp.bash` | The task says "the existing PV". The UID is how the grader proves the volume was reused and not replaced. |
| 5 | The text that was actually written to the file, recorded at setup time | `LabSetUp.bash` | The live check compares the served body against the truth rather than against a guess. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | PersistentVolumeClaim `pvc001` in namespace `web`, Bound, `volumeName: pvvol` | `LabValidate.bash` |
| B | The claim's storage class equal to the PV's, and its request 200Mi / ReadWriteOnce | `LabValidate.bash` |
| C | PersistentVolume `pvvol` unchanged — same UID | `LabValidate.bash` |
| D | Deployment `web` mounting the claim at `/usr/share/nginx/html`, with ready replicas | `LabValidate.bash` |
| E | Service `web` on port 80, selecting the pods, with endpoints | `LabValidate.bash` |
| F | The Service actually serves the file that was already on the volume | `LabValidate.bash` — a live curl of the Service's ClusterIP, falling back to a curl from inside the cluster |

## Gotchas

- **A PV and a PVC bind only when the access modes, the size and the
  StorageClass all agree.** The size is the one people get wrong: the request
  must be no LARGER than the volume's capacity, but it may be smaller. A 200Mi
  request against a 1Gi volume binds fine, and the claim then reports the
  VOLUME's capacity — `.status.capacity.storage` is 1Gi even though
  `.spec.resources.requests.storage` is 200Mi. That is the detail this
  question turns on.

- **The access modes do not have to be equal, either.** The claim's modes have
  to be a SUBSET of the volume's. `pvvol` offers ReadWriteMany, so a claim
  asking for ReadWriteOnce is a subset and binds; a claim asking for
  ReadWriteMany against a ReadWriteOnce volume would never bind.

- **The StorageClass has to match, including the empty one.** `pvvol` carries
  `storageClassName: ""`. A claim that omits the field is DEFAULTED by the API
  server to the cluster's default class — and then it does not match, and it
  sits Pending with "no matching persistent volumes found". If the cluster has
  a default class with a provisioner, that claim is not even Pending: it is
  dynamically provisioned onto a brand-new volume, and you end up with a
  working claim that is bound to the wrong thing. Write `storageClassName: ""`
  explicitly.

- **A hostPath is node-local.** The data on `/opt/shared` exists on one node
  and nowhere else, which is why the PV is pinned to that node with a node
  affinity: the scheduler will only place a pod that uses the claim on that
  node, so the pod sees the data that was seeded.

- **The claim has to be there before the Deployment.** A Deployment that
  references a claim that does not exist yet is not an error — the pod stays
  Pending with "persistentvolumeclaim not found" until the claim appears. The
  order still saves you a confusing wait.

- **The Service is not done until it has endpoints.** A Service with a
  selector that matches nothing still exists, still has its ClusterIP and
  still answers on port 80 — with a connection refused or an empty response
  from nginx's neighbours rather than from your pods. That is why the grader
  curls it instead of reading the object.

- **`nginx` serves `index.html` from `/usr/share/nginx/html`.** The seeded
  file has to be named `index.html` for a request for `/` to return it, and it
  has to sit at the root of the mounted directory.

## Environment requirements

- A cluster with at least one schedulable node that is not tainted
  `NoSchedule` — the setup picks such a node, and warns if there is none.
- Registry access for `nginx:1.28` and for `busybox:1.36`.
- The validator curls the Service's ClusterIP from the machine it runs on; if
  that address is not reachable from there, it curls it from a pod inside the
  cluster instead.
- Kubernetes 1.20 or newer. Nothing in this question depends on a feature
  gate.
