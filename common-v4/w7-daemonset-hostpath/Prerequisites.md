# w7 — One pod on every node: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `agent` | `LabSetUp.bash` | The DaemonSet lives here and the task names the namespace. |
| 2 | ConfigMap `fluentd-config` — the agent's configuration, under the keys `fluent-bit.conf` (a fluent-bit style configuration) and `fluent.conf` (the same thing in the syntax the fluentd image actually reads) | `LabSetUp.bash` | The configuration the agent would run with. The task does not ask you to mount it, but it is there, and the gotchas below explain what happens if you do. |
| 3 | The cluster's nodes | the cluster | The DaemonSet is placed by the DaemonSet controller, which wants one pod per node. The number of nodes is what `DESIRED` is measured against. |
| 4 | The control-plane node, tainted `NoSchedule` | the cluster (or `LabSetUp.bash`, if the cluster does not already taint it) | This is the hard part of the question. The DaemonSet controller wants a pod on the tainted node too, but the pod will not run there until the template tolerates the taint. |
| 5 | The effective control-plane taint key and effect, recorded at setup time | `LabSetUp.bash` | The validator checks that the toleration covers the taint the cluster actually carries, not one it guessed. |
| 6 | The node count, recorded at setup time | `LabSetUp.bash` | Printed in the setup summary, and used to explain the probe result. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | DaemonSet `fluentd` in namespace `agent`, image `quay.io/fluentd/fluentd:v1.6` | `LabValidate.bash` |
| B | `hostNetwork: true` on the pod template | `LabValidate.bash` |
| C | Exactly two hostPath volumes: `varlog` at `/var/log` and `varlibdockercontainers` at `/var/lib/docker/containers` | `LabValidate.bash` |
| D | The two volumes mounted at `/var/log` and `/var/lib/docker/containers` | `LabValidate.bash` |
| E | A toleration covering the control-plane taint | `LabValidate.bash` — against the taint the setup recorded |
| F | `desiredNumberScheduled` equal to the number of nodes, `numberReady` equal to `desiredNumberScheduled`, every pod Ready | `LabValidate.bash` |

## Gotchas

- **A DaemonSet's scheduler is the DaemonSet controller, not the default one.**
  It ignores a node's `unschedulable` flag — a cordoned node still gets a pod —
  but it DOES respect taints: the control-plane node is tainted, so without a
  toleration the pod is skipped there and `DESIRED` stops being the number of
  nodes. That is the whole of step 4.

- **The toleration has to name the taint, or cover everything.** A taint
  `node-role.kubernetes.io/control-plane:NoSchedule` is matched by a toleration
  with that key and either no `effect` (which tolerates every effect) or
  `effect: NoSchedule`. A toleration with `operator: Exists` and an empty key
  tolerates every taint on every node. A toleration for a key the node does
  not carry tolerates nothing.

- **The control-plane key is not always the same.** A current kubeadm cluster
  taints the control plane with `node-role.kubernetes.io/control-plane`; an
  older one uses `node-role.kubernetes.io/master`. Look at the node before you
  write the toleration.

- **A hostPath volume resolves on the node, not on the machine running
  kubectl.** That is why the two paths are different things: the `path` is a
  directory on the NODE the pod lands on, and the `mountPath` is where that
  directory appears inside the container. Writing `/var/log` as the mountPath
  and `/var/log` as the path looks right because they happen to be equal here;
  they are equal by choice, not by rule.

- **`/var/lib/docker/containers` does not exist on a containerd-based node.**
  A hostPath with the default type does not create anything, so the kubelet
  cannot set the volume up and the pod never starts. Use
  `hostPath.type: DirectoryOrCreate` and the kubelet creates the directory on
  the node instead of refusing the pod.

- **Mounting the ConfigMap over the wrong path stops the agent.** The image is
  fluentd, and it reads `/fluentd/etc/fluent.conf`. The ConfigMap holds a
  fluent-bit style configuration under `fluent-bit.conf`, which fluentd cannot
  parse — mount that key over `/fluentd/etc/fluent.conf` and the agent dies on
  startup. Mount the whole ConfigMap at `/fluentd/etc` instead, or do not mount
  it at all; the task does not ask you to.

- **A nodeSelector is the easy way to fail this.** It takes the DaemonSet off
  every node the selector does not match, and `DESIRED` stops being the number
  of nodes. The same goes for an `affinity` block that is too narrow.

## Environment requirements

- A cluster with at least one node, and a control-plane node that is tainted
  `NoSchedule` — the setup adds that taint if the cluster does not have it,
  and the reset removes it again.
- Registry access for `quay.io/fluentd/fluentd:v1.6` on every node, including
  the control-plane node.
- Kubernetes 1.16 or newer. `hostPath.type` and the DaemonSet's behaviour
  towards tainted nodes are both long-established.
