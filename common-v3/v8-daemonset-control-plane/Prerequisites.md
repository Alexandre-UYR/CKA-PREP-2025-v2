# v8 — One pod per node, including the control plane: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `ds` | `LabSetUp.bash` | The task names the namespace, and the DaemonSet and its pods live there. |
| 2 | A control-plane node | the cluster | A DaemonSet that runs on every node has to cope with the control-plane node, which is a different kind of node from the workers. |
| 3 | The node carries the taint `node-role.kubernetes.io/control-plane:NoSchedule` | `LabSetUp.bash` — the taint is added if the cluster does not already have it, and the key is recorded in `/tmp/cka-lab/v8.taint` | This is the breakage. kubeadm taints the control-plane node so that ordinary workloads stay off it, and a DaemonSet that does not tolerate the taint is skipped there. The pod is created and then sits Pending forever. |
| 4 | A node labelled `monitoring=yes` | `LabSetUp.bash` | The trap in the other direction. The label looks like a reason to write `nodeSelector: {monitoring: yes}` — which takes the DaemonSet off every node that does not carry the label, control plane included. |
| 5 | More than one node if the cluster has them | the cluster | With one node the question is trivial, so the exercise wants at least a control-plane node and one worker. The setup works with a single node too — the DaemonSet then simply has to land on the tainted one. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | A DaemonSet `agent` in namespace `ds` | `LabValidate.bash` |
| B | `.spec.template.spec.hostNetwork` is `true` | `LabValidate.bash` |
| C | A toleration in the pod template whose key is `node-role.kubernetes.io/control-plane`, with an effect that covers the node's taint (or no effect at all) | `LabValidate.bash` |
| D | `.status.desiredNumberScheduled` equals the number of nodes in the cluster — a nodeSelector that restricts the DaemonSet fails here | `LabValidate.bash` |
| E | `.status.numberReady` equals `.status.desiredNumberScheduled` | `LabValidate.bash` |
| F | One pod per node, every one of them Ready | `LabValidate.bash` |

## Gotchas

- **The DaemonSet's scheduler is the DaemonSet controller, not the default
  scheduler.** The controller decides which nodes should run a copy of the pod
  and creates one pod per node. It does *not* respect a node's `unschedulable`
  flag the way the default scheduler does, but it *does* respect taints — a
  tainted node is skipped unless the pod template tolerates the taint. That is
  why the control-plane node needs an explicit toleration, and it is the whole
  question.

- **A toleration alone is not enough.** The pod still has to fit on the node:
  the image has to pull, the container has to start, and the resource requests
  have to fit. If the pod stays Pending on the control-plane node for a
  different reason, READY will never catch up with DESIRED.

- **`desiredNumberScheduled` counts the tainted node.** The controller wants a
  pod on every node that matches the pod's node selector and node affinity —
  taints are not part of that count. So a DaemonSet with no toleration reports
  DESIRED = number of nodes and READY = one less. That gap is the symptom.

- **A nodeSelector is the trap.** `nodeSelector: {monitoring: yes}` gives you
  exactly one pod, on the wrong node, and DESIRED drops to 1. The `monitoring=yes`
  label is on a node like any other; the task says *every* node.

- **`hostNetwork: true` and DNS.** A pod on the host network does not get the
  cluster's DNS settings unless you also set `dnsPolicy: ClusterFirstWithHostNet`.
  The task does not ask for it, but an agent that reports by hostname will
  not resolve anything without it.

- **The taint belongs to the cluster.** The setup adds it if the cluster does
  not have it and the reset deliberately leaves it in place, so a cluster that
  was not tainted before the exercise stays tainted afterwards. The reset
  restores the question's objects, not the cluster's taints.

## Environment requirements

- A cluster with at least one node, and a control-plane node in it. Two or
  three nodes make the question clearer than one.
- Registry access for `busybox:1.36` — the setup's probe uses it, and it is
  also a good image for the agent itself.
- No special components. This is the DaemonSet controller and the scheduler
  behaving exactly as documented.
