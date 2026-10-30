# x2 — Take a copy of the cluster's brain: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | A kubeadm cluster whose etcd runs as a **static pod** | the cluster | In a kubeadm cluster etcd is not an ordinary workload: its Pod manifest lives on the control-plane node at `/etc/kubernetes/manifests/etcd.yaml`, and the kubelet starts it and keeps it running. Static does not mean unreachable — etcd listens on a port **on the node itself**, so the snapshot is taken from the node, without going through kubectl at all. |
| 2 | The etcd PKI in `/etc/kubernetes/pki/etcd/` — `ca.crt`, plus a client certificate and key | the cluster | etcd is TLS-only. The **CA certificate** is what lets the client verify the server's identity; the **client certificate and key** are what authenticate *you* to etcd. All three are needed. Without them the connection is refused, and that is not negotiable — there is no plaintext listener to fall back on. |
| 3 | The etcd client endpoint, normally `https://127.0.0.1:2379` | the cluster | The address the snapshot tool dials. The setup reads it out of the static pod's manifest, so it is the port this cluster really uses rather than the one you assume it uses. |
| 4 | `etcdctl` or `etcdutl` on the node | the node, or the candidate | The tool that takes and inspects the snapshot. The setup checks for both and records which one it found; if neither is installed it says so and still finishes, and the file itself is still graded. |
| 5 | The endpoint, the three certificate paths and the tool name recorded in `/tmp/cka-lab/x2.env` | `LabSetUp.bash` | So the grader talks to etcd with exactly the same endpoint and certificates the candidate was told about, instead of guessing them. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | The file `~/snapshotdb` | `LabValidate.bash` |
| B | The file is not empty | `LabValidate.bash` |
| C | `etcdutl snapshot status ~/snapshotdb` (or the `etcdctl` equivalent) succeeds against it | `LabValidate.bash` — skipped with a reason if neither tool is installed on the node |
| D | The snapshot reports a non-zero revision count | `LabValidate.bash` — skipped if no tool is available, and covered by the file-signature check instead |
| E | The control plane was not stopped to take the snapshot | `LabValidate.bash` |

## Gotchas

- **etcd is a static pod, and that is not a problem.** The first instinct is
  that you cannot reach etcd "because it is not in the cluster as a normal
  Deployment". You can. The static pod's manifest is on the node, the process
  is listening on the node, and the certificates that the port demands are on
  the node too. Everything this question needs is three directories away.

- **The three certificates are not optional.** etcd is TLS-only — there is no
  plaintext port to fall back on. The **CA certificate** (`ca.crt`) is what
  proves the server is the server; the **client certificate and key** are what
  prove *you* are allowed in. Handing etcd the server's own certificate and key
  instead of a client pair does not work: the server certificate is issued for
  server authentication, not client authentication. The kubeadm PKI directory
  holds ready-made client pairs — `healthcheck-client.crt`/`.key` and
  `apiserver-etcd-client.crt`/`.key` — and either of them will do.

- **`etcdctl` needs `ETCDCTL_API=3`.** The old v2 API and the v3 API are
  different commands. A snapshot of a v3 database is taken with the v3 API.

- **`etcdutl` and `etcdctl` are not the same tool.** `etcdutl snapshot save`
  and `etcdctl snapshot save` both write a snapshot, but only `etcdctl` has
  the `--endpoints`, `--cacert`, `--cert` and `--key` flags in the same place
  — for `etcdutl` the same flags exist, but the file has to come last.

- **Do not stop the control plane.** Stopping etcd to take a copy defeats the
  purpose: a stopped etcd is an unavailable cluster, and the snapshot is
  supposed to be taken from a healthy one. `etcdctl snapshot save` is a
  read-and-copy operation; the database keeps serving while it runs.

- **A file called `snapshotdb` is not a snapshot.** The grader reads the
  snapshot back with the tool. An empty file, or a text file with a
  plausible name, is caught.

## Environment requirements

- A kubeadm cluster, and shell access to its **control-plane node** — this
  question is run on the node, not through kubectl.
- The etcd static pod running, with its manifest at
  `/etc/kubernetes/manifests/etcd.yaml`.
- The etcd PKI present under `/etc/kubernetes/pki/etcd/`.
- `etcdctl` or `etcdutl` on the node. Without one, the setup still finishes
  and the snapshot file is still graded; only the tool-backed checks are
  skipped.
- Root, or `sudo`, on the node: the PKI and the log directories are root's.
