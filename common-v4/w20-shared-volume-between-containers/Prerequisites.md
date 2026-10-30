# w20 — One volume, two containers: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `shared` | `LabSetUp.bash` | The Pod lives here, and the task names the namespace. The setup deletes and re-creates the namespace on each run, so a Pod left over from an earlier attempt cannot answer the validation. |
| 2 | Pod `writer` with ONE container, busybox:1.36, running `sh -c 'echo hello > /data/hi; sleep 10000'` | `LabSetUp.bash` | The container that does the writing. The task says the second container must read what the FIRST one wrote, so there has to be a first container, and it has to have written something. |
| 3 | An emptyDir volume named `work` mounted at /data in that container | `LabSetUp.bash` | The volume that is going to be shared. It is the thing the second container has to mount too. |
| 4 | The file /data/hi really exists, with the content `hello` | `LabSetUp.bash` | The setup waits for it rather than assuming it. A pre-state where the file is not there yet makes the live check meaningless. |
| 5 | The Pod is Running with its container Ready | `LabSetUp.bash` | The live check execs into a container, which needs a running Pod. |
| 6 | Registry access for `busybox:1.36` | the environment | The candidate's second container has to be pullable, or the Pod never becomes ready and the grader cannot tell a broken Pod from a broken image pull. |
| 7 | A writable `/root` on the machine running `kubectl` | the environment | Not needed for this question — no file is graded — but the candidate usually writes one anyway while working. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | Pod `writer` in namespace `shared` with exactly two containers | `LabValidate.bash` — the container count is read from the spec |
| B | Both containers mount the SAME volume — the same volume NAME — at /data | `LabValidate.bash` — the mount name is read out of each container's `volumeMounts` and the two are compared, and the mount path is checked |
| C | That volume is an emptyDir | `LabValidate.bash` — the named volume is looked up in `spec.volumes` and its type is checked |
| D | The Pod is Running and both containers are Ready | `LabValidate.bash` — the phase, and the ready flag of each container status |
| E | The second container can read /data/hi | `LabValidate.bash` — a live check: `kubectl exec` into the SECOND container and `cat /data/hi` has to return `hello` |
| F | The two containers really share one directory | `LabValidate.bash` — a live check: a marker file written in the first container is read back in the second |

## Gotchas

- **An emptyDir belongs to the POD, not to a container.** Every container in
  that Pod sees the same directory, and the file the first container wrote is
  still there. That is the whole point of the question: the second container
  mounts the same volume and finds the first container's file.

- **Another Pod gets a DIFFERENT emptyDir even if it is named the same.** Two
  Pods each with a volume called `work` have two unrelated directories. That
  is what a PersistentVolume is for: a PV is a storage object outside the
  Pod, so several Pods can attach the same one.

- **The container list of a running Pod cannot be changed.** `kubectl patch
  pod writer` with a second container is rejected: only the image of an
  existing container may be changed. The way to add a container is to delete
  the Pod and create it again with both containers, keeping the name `writer`.
  The emptyDir is re-created empty, so the first container has to write
  /data/hi again — which it does, because it still runs the same command.
  Check the file afterwards rather than assuming it survived.

- **The volume NAME is what ties the two containers together.** Both
  `volumeMounts` must use the same name, and that name has to match a volume
  in `spec.volumes`. Two containers that each mount a volume called `work`,
  where the Pod only declares one `work`, is not a shared volume.

- **Both containers have to mount it at /data.** A second container that
  mounts the volume at /var/data can still read the file — but only after
  `cat /var/data/hi`, and the task says /data.

- **A container that exits takes the Pod down with it.** The containers of a
  Pod share a lifecycle: if one of them finishes, the kubelet restarts the
  Pod rather than just that container. The second container therefore has to
  be long-running too — `sleep 10000` or similar, not a one-shot `cat`.

- **`kubectl exec` needs `-c` once a Pod has more than one container.** With
  two containers, `kubectl exec writer -- cat /data/hi` goes to the default
  container, which is the FIRST one. To read the file from the second
  container you have to name it: `kubectl exec writer -c <name> -- cat /data/hi`.

## Environment requirements

- A cluster with at least one node, and registry access for `busybox:1.36`.
- `kubectl exec` has to work: the live checks run commands inside the
  containers.
- No special components. This is a plain Pod, an emptyDir and two containers.
