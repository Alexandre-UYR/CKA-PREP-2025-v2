# Q3 — Sidecar: prerequisite inventory

The task is to turn a single-container Deployment into a two-container pod that
shares a log file. For the sidecar to be able to read what the main container
writes, the two containers have to mount the *same* volume at the same path, and
the main container has to actually be writing to that path. Both of those facts
have to be true in the pre-state, which is what this inventory is about.

## Prerequisite inventory

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Deployment `wordpress` in the default namespace, 1 replica | LabSetUp.bash | The task says "update the existing wordpress deployment". There has to be an existing deployment, and it has to be *updated* rather than re-created (the grader compares its UID). |
| 2 | Pod template with exactly one container named `wordpress` | LabSetUp.bash | The task adds a *second* container. The pod template must have a place to add it, and the main container must be there to share the volume with. |
| 3 | Main container image `wordpress:php8.2-apache` | LabSetUp.bash | The image the workload runs on; it must stay the same, only the pod template changes. |
| 4 | The main container's command writes to `/var/log/wordpress.log` | LabSetUp.bash | This is the file the sidecar has to tail. It is written every 5 seconds, so the file exists shortly after the pod starts. |
| 5 | No volume mounted at `/var/log` yet | LabSetUp.bash | The volume is what the candidate has to add. If the setup already mounted one, there would be nothing to do. |
| 6 | Service `wordpress` selecting `app: wordpress` | LabSetUp.bash | Part of the pre-state the exam hands you; it must still point at the pods after the change, and the reset has to remove it again. |
| 7 | Deployment pod labels `app: wordpress` | LabSetUp.bash | The Service selector and the grader's pod lookup both use this label. |
| 8 | `/tmp/cka-lab/q3.deploy.uid` | LabSetUp.bash | The UID of the deployment as the setup left it. The grader compares it with the UID at validation time: deleting the deployment and creating a new one changes the UID, and that is how "you updated the existing deployment" is proved. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| 1 | The **same** deployment, updated (not re-created) | `LabValidate.bash`: "Deployment wordpress is the SAME deployment created during setup (it was updated, not deleted and re-created)" |
| 2 | Exactly 2 containers in the pod template | `LabValidate.bash`: "The pod template has exactly 2 containers (wordpress + sidecar)" |
| 3 | A container named `sidecar` with image `busybox:stable` | `LabValidate.bash`: "Container sidecar uses image busybox:stable" |
| 4 | That container runs `/bin/sh -c tail -f /var/log/wordpress.log` | `LabValidate.bash`: "Container sidecar runs 'tail -f /var/log/wordpress.log'" (the command may be split across `command` and `args`, both are inspected) |
| 5 | A volume mounted at `/var/log` in **both** containers | `LabValidate.bash`: "Container wordpress mounts a volume at /var/log", "Container sidecar mounts a volume at /var/log" |
| 6 | Both containers mount the **same** volume (same volume name) | `LabValidate.bash`: "Both containers mount the SAME volume (that is what makes the log file shared)" |
| 7 | The pod still healthy | `LabValidate.bash`: "Deployment wordpress has 1 ready replica" |
| 8 | The shared volume really works | `LabValidate.bash`: "The shared volume works: /var/log/wordpress.log is visible inside the sidecar container" |

## Gotchas

- **Both containers need the mount.** The task says "use a volume mounted at
  `/var/log` to make the log file available to the co-located container". If
  only the sidecar mounts the volume, the main container keeps writing to its
  own `/var/log` inside the image, the sidecar's `/var/log` stays empty, and
  `tail -f` dies on a missing file.
- **Same volume name, not just same path.** Two different volumes mounted at
  `/var/log` in the two containers are two different directories. The volume
  *name* has to match; the path alone is not enough. `emptyDir` is the usual
  choice, and it is enough here because the two containers live in the same
  pod.
- **The sidecar can crash on the first try.** `tail -f` fails immediately if
  `/var/log/wordpress.log` does not exist yet, and a container that exits is
  restarted. Put the sidecar **after** the `wordpress` container in the
  container list: the kubelet starts containers in order, so the writer is
  already running when the sidecar starts. If you still see `tail: can't open
  '/var/log/wordpress.log' for reading`, wait for the backoff and it settles.
- **Do not delete and re-create the deployment.** `kubectl delete deploy
  wordpress` followed by `kubectl apply` gives you a working sidecar and still
  fails the question: the UID changes. Use `kubectl edit` or `kubectl patch`
  (or apply a manifest that only changes `spec.template`).
- **A rollout replaces the pod.** After editing the template, wait for it:
  `kubectl rollout status deployment/wordpress`. The old pod goes away and a new
  one is created; the log file inside a new pod starts empty, so the sidecar
  needs the file to be recreated by the writer.
- **Editing the pod template is what triggers the rollout.** A change to
  `spec.template` is what makes the Deployment create a new pod; a change to
  the Deployment's own metadata does not.
- **The container name matters.** It has to be exactly `sidecar`; the grader
  looks it up by name.

## Environment requirements

- A Kubernetes cluster with a working `kubectl` context and the default
  namespace.
- The `wordpress:php8.2-apache` and `busybox:stable` images pullable.
- Enough room in the cluster for a 1-replica Deployment plus its sidecar.
- The lab has to run on the machine that has `kubectl` configured, because
  `/tmp/cka-lab/q3.deploy.uid` is a file on that machine.
