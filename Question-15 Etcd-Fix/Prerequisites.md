# Q15 — etcd fix: prerequisite inventory

This question **breaks the cluster on purpose**. `kubectl` does not work at all
while the question is in its starting state, so the grader and the reset run on
the **control-plane node**, inspecting files and the container runtime directly.

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | A single-node (or control-plane) cluster whose kube-apiserver is a **static pod** managed by kubelet | the playground | The fix is made by editing the static pod manifest on disk. A managed control plane (EKS, GKE, AKS) has no such file and the question cannot be done there at all. |
| 2 | The manifest at `/etc/kubernetes/manifests/kube-apiserver.yaml`, containing `--etcd-servers=https://127.0.0.1:2379` | kubeadm, during the cluster's bootstrap | This is the file the task is about. The `2379` is etcd's **client** port — the one the apiserver talks to. |
| 3 | etcd listening on `127.0.0.1:2379` with the PKI in `/etc/kubernetes/pki/etcd/` | kubeadm | The apiserver can only come back if etcd is actually there and healthy on the client port. |
| 4 | The manifest broken: `2379` replaced by `2380` | `LabSetUp.bash`, with `sed 's/:2379/:2380/g'` | This is the incident. `2380` is etcd's **peer** port — the port etcd uses to talk to *other* etcd members. Pointing a client at it is exactly the kind of mistake a migration makes. |
| 5 | A pristine copy of the working manifest | `LabSetUp.bash`, into `/root/kube-apiserver.yaml.pristine` (and `.bak`) | Both the setup and the reset build on it, so the question can be run again and again. Without it, a second setup would back up the *already broken* manifest and the original would be lost. |
| 6 | Root, or a user with passwordless `sudo` | the node itself | The manifest is root-owned, and `crictl` needs root to talk to the container runtime socket. |

## What the candidate must create

There is nothing to "create" here. The candidate must **repair**:

| # | Deliverable | Checked by |
|---|---|---|
| A | The manifest no longer points at the peer port 2380 | `LabValidate.bash` |
| B | The manifest points at the client port 2379 again | `LabValidate.bash` |
| C | The kube-apiserver static pod is running | `LabValidate.bash` (`crictl ps`) |
| D | The API server answers again | `LabValidate.bash` (`kubectl get nodes`) |

## Gotchas

- **2379 is the client port, 2380 is the peer port.** The apiserver is a
  *client* of etcd. etcd's peer port is for etcd-to-etcd replication and speaks
  a different protocol; pointing a client at it produces a connection error, not
  a slow response.

- **Editing the manifest is enough — kubelet restarts the static pod.** The
  static pod is reconciled from that file continuously. Save the file and wait;
  there is no `kubectl delete pod` to run, because you cannot use kubectl.

- **The apiserver takes a moment to come back.** The validator waits up to
  about two minutes for it, because the static pod has to be restarted and
  then has to reconnect to etcd.

- **Check the logs, not just the file.** `sudo crictl logs <id>` on the
  apiserver container shows the real error. On the exam the error usually names
  the endpoint it could not reach.

- **The scheduler and controller-manager can break the same way.** They also
  talk to etcd, and they also carry an `--etcd-servers` flag. If the apiserver
  comes back but the rest of the control plane is still unhealthy, check
  `/etc/kubernetes/manifests/kube-scheduler.yaml` and `kube-controller-manager.yaml`
  for the same mistake.

## Environment requirements

- **Control-plane node access.** This is not a `kubectl` question. Run the
  setup, the validator and the reset on the node itself — over SSH on
  Killercoda, or `docker exec -it <cluster>-control-plane bash` on kind.
- `sudo` on that node.
- `crictl` on the node for the container checks (it ships with kubeadm nodes).
- On kind, `export KUBECONFIG=/etc/kubernetes/admin.conf` once you are inside
  the control-plane container, otherwise `kubectl get nodes` in the validator
  cannot authenticate.
