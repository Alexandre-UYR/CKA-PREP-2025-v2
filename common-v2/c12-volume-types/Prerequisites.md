# c12 — The four everyday volume types: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `volumes` | `LabSetUp.bash` | The Pod, the ConfigMap and the Secret all live in it, and every command in the task is namespaced to it. |
| 2 | ConfigMap `app-config` with the key `nginx.conf` | `LabSetUp.bash` | The Pod mounts it as a volume. A ConfigMap mounted as a volume appears as **one file per key**, so the key name is the file name inside the mount — which is why the live check looks for `nginx.conf` and not for a key called `config`. |
| 3 | Secret `app-secret` with one key | `LabSetUp.bash` | The Pod mounts it as a volume. A Secret mounted as a volume appears the same way as a ConfigMap — one file per key — but the kubelet decodes the base64 for you, so the file inside the mount holds the plaintext value. |
| 4 | The directory `/tmp/hostdata` on the node, created through a short-lived Pod that mounts the same hostPath | `LabSetUp.bash` | The Pod mounts it as a hostPath. A hostPath resolves on the **node**, not on the machine running `kubectl`, so `mkdir` on your laptop does nothing for it. The setup runs a Pod with `hostPath.type: DirectoryOrCreate` pinned to each node, which makes the kubelet create the directory there. The directory has to exist before the candidate's Pod lands, because a hostPath with the default type `Directory` refuses to start when the path is missing. |
| 5 | A cluster with a working scheduler and at least one node that can run `nginx:1.25` and `busybox:1.36` | the cluster itself | The Pod has to be Running for the live checks to mean anything, and the setup's helper Pod needs the busybox image to create the host directory. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | Pod `all-volumes` in namespace `volumes` | `LabValidate.bash` |
| B | The Pod is Running | `LabValidate.bash` |
| C | Exactly four volumes in the Pod template | `LabValidate.bash` |
| D | Exactly one emptyDir, one ConfigMap volume, one Secret volume, one hostPath volume | `LabValidate.bash` |
| E | The ConfigMap volume uses `app-config`, the Secret volume uses `app-secret`, the hostPath is `/tmp/hostdata` | `LabValidate.bash` |
| F | The emptyDir is mounted at `/tmp` | `LabValidate.bash` |
| G | The ConfigMap volume is mounted at `/etc/config` | `LabValidate.bash` |
| H | The Secret volume is mounted at `/etc/secret` | `LabValidate.bash` |
| I | The hostPath volume is mounted at `/host` | `LabValidate.bash` |
| J | Live: `ls /etc/config` inside the Pod lists `nginx.conf` | `LabValidate.bash` (live exec) |
| K | Live: `ls /etc/secret` inside the Pod is not empty | `LabValidate.bash` (live exec) |
| L | Live: `ls /tmp` inside the Pod works | `LabValidate.bash` (live exec) |

The grader identifies each volume by its **source** — emptyDir, ConfigMap
`app-config`, Secret `app-secret`, hostPath `/tmp/hostdata` — and by the
**mount path** it ends up at. The volume *names* (`tmp`, `cfg`, `sec`,
`host`) are what the task asks for and are the sensible thing to use, but they
are not what the grader keys on.

## Gotchas

- **A ConfigMap mounted as a volume appears as files, one per key, and it is
  read-only.** The key `nginx.conf` becomes the file `/etc/config/nginx.conf`.
  Nothing else is there — no directory tree from the ConfigMap, no "the
  ConfigMap" object. Write into the mount and the kubelet gives you a
  read-only filesystem error.

- **A Secret mounted as a volume appears the same way, but decoded.** The
  Secret's `data` field holds base64; the kubelet decodes it when it writes
  the file, so `/etc/secret/api-key` contains the plaintext. If you were to
  base64 the value yourself before putting it in the Secret, the file inside
  the mount would contain double-encoded junk. (`stringData` in the manifest
  is the shortcut: the API server encodes it for you.)

- **An emptyDir lives and dies with the Pod.** It is created when the Pod is
  scheduled and deleted when the Pod goes away — including when the Pod is
  deleted and recreated. Nothing survives a restart of the Pod, and it is
  not shared with any other Pod.

- **A hostPath is the node's own filesystem.** It is there whether or not a
  Pod is using it, it is not namespaced, and it is not cleaned up when the
  Pod is deleted. It is also the one that needs care about **which node the
  Pod landed on**: `/tmp/hostdata` exists on the node the setup prepared, and
  if the Pod is scheduled somewhere else the path is missing and the Pod
  refuses to start. A hostPath with `type: DirectoryOrCreate` creates the
  directory if it is missing (kubelet creates it, with kubelet's ownership);
  `type: Directory` fails when it is missing.

- **A volume is not a mount.** Declaring `volumes:` gives the Pod a place to
  put data; nothing appears in the container until a `volumeMount` names that
  volume and gives it a `mountPath`. A volume with no mount is invisible.

- **The mount path is a directory, and it hides what was there.** Mounting
  the emptyDir at `/tmp` puts the emptyDir's contents at `/tmp` and hides the
  image's original `/tmp`. Mounting the ConfigMap at `/etc/config` hides the
  image's `/etc/config` — if the image had one, it is gone.

- **The volumeMount refers to the volume by name, not by type or path.** A
  `volumeMount` whose `name` does not match a volume in `spec.volumes` is
  rejected by the API server: `spec.containers[0].volumeMounts[0].name: Not
  found: "cfg"`.

- **Mounting a ConfigMap does not make it read-write.** Use `subPath` if you
  want to project a single file, and remember that a `subPath` mount does
  not receive updates when the ConfigMap changes.

## Environment requirements

- A cluster with at least one node and a working scheduler.
- Registry access for `nginx:1.25` and `busybox:1.36`.
- Permission to create Pods, ConfigMaps and Secrets in namespace `volumes`,
  and to pin a Pod to a node with `spec.nodeName` (the setup and the reset
  both do this to create and remove the host directory).
- Write access to `/tmp` on the nodes — the host directory is created under
  `/tmp/hostdata`.
- Nothing else: no CSI driver, no provisioner and no StorageClass are
  involved in this question.
