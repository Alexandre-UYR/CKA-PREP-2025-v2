# x3 — Which log belongs to which component: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | A kubeadm cluster, and shell access to its **control-plane node** | the cluster | This is a node-level question. The components being looked for are not all running on the same machine, and two of them run on every node — so the logs have to be found on the machine, not in the API. |
| 2 | The control plane's static pods running — `kube-apiserver`, `kube-controller-manager`, `kube-scheduler` | the cluster | Their manifests live in `/etc/kubernetes/manifests/`, the kubelet starts them, and their output is collected into `/var/log/containers/`. The kubelet then makes a **symlink** under `/var/log` named after each container. That symlink is the answer to "where is the API server's log". |
| 3 | The kubelet running on the node | the cluster | The kubelet's own log is a file of its own under `/var/log` — it is not one of the container logs, because the kubelet is not running in a container. |
| 4 | kube-proxy running on the node | the cluster | The fifth component. It runs as a DaemonSet pod, so its log lands in `/var/log/containers/` with a symlink beside it, like the control plane's own components. |
| 5 | The log files that actually exist on this node, recorded in `/tmp/cka-lab/x3.logs` | `LabSetUp.bash` | The grader reads this to know which of the five components this node really has a log for. Where the node has no such file — a kubelet that logs only to the journal, for instance — that line is skipped rather than failed, because the environment cannot support it. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | `/root/control-plane-logs.txt`, with five non-empty lines | `LabValidate.bash` |
| B | Line 1 is the API server's log, line 2 the scheduler's, line 3 the controller manager's, line 4 the kubelet's, line 5 the kube-proxy's — matched on the file's name, not on an exact path | `LabValidate.bash` |
| C | Every path in the file exists on this node | `LabValidate.bash` |
| D | `/root/scheduler-component.txt` holds the name of the component that makes scheduling decisions | `LabValidate.bash` |

## Gotchas

- **The components do not log to the same place.** The kubelet's log is a plain
  file under `/var/log` (`/var/log/kubelet.log`) — the kubelet is not running
  in a container, so there is no container log for it. The control plane's own
  components run as **static pods**, so their output is collected under
  `/var/log/containers/`, and the kubelet makes a **symlink** beside them under
  `/var/log` named after the container: `/var/log/kube-apiserver.log`,
  `/var/log/kube-scheduler.log`, `/var/log/kube-controller-manager.log`.
  kube-proxy, which is a DaemonSet pod, gets the same treatment:
  `/var/log/kube-proxy.log`.

- **`/var/log/apiserver.log` does not exist.** The names in the question are
  the plain English names of the components; the files on a kubeadm node carry
  the `kube-` prefix. The grader matches on the **file's name** rather than on
  an exact path, so either the symlink or the real file under
  `/var/log/containers/` is accepted.

- **The files are root's.** They live in root-owned directories, so reading
  them may need `sudo`. The grader reads them with `sudo` when it has to.

- **The symlink points at a directory with a long name in it.** A container
  log path looks like
  `/var/log/containers/kube-apiserver-node1_kube-system_kube-apiserver-node1_<uid>/0.log`.
  That is the file; the symlink is the tidier answer.

- **There are more logs than the five asked for.** The kubelet and
  kube-proxy both log on every node, and the static pods also leave logs
  behind in `/var/log/containers/` for other containers. The five asked for
  have to be identified by *name*, not by picking the first five files in the
  directory.

- **The scheduler decides where a Pod runs.** The API server serves the API,
  the scheduler decides **where** a pod runs, the controller manager
  reconciles the state you asked for, and kube-proxy programs the node's
  network rules. The component whose name goes in
  `/root/scheduler-component.txt` is `scheduler` — the file is named
  `kube-scheduler` on disk, so write the component's name, not the log file's
  name.

## Environment requirements

- A kubeadm cluster, and shell access to its **control-plane node**.
- The control plane's static pods running, so that their container logs and
  the kubelet's symlinks exist.
- kube-proxy running on the node. If it is not there, that line of the answer
  is skipped rather than failed.
- Root, or `sudo`, on the node: `/var/log` is root's.
