# c29 — Count the nodes that are actually usable: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | A cluster with at least one node | the cluster itself | The task is to count nodes, so there has to be something to count. |
| 2 | A control-plane node identifiable by the taint `node-role.kubernetes.io/control-plane:NoSchedule` | the cluster itself | The task says to exclude the control plane, and names the taint that identifies it. This is what makes the exclusion precise rather than a guess about which node is which. |
| 3 | At least one non-control-plane node | the cluster itself | Otherwise the answer is 0 and the question teaches nothing. |
| 4 | A record of the cluster's nodes and their taints | `LabSetUp.bash`, into `/tmp/cka-lab/c29.nodes` | So the candidate can see the starting point and check their work against it. |

The setup **creates nothing and changes nothing**. It only reads the cluster.

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | `/root/ready-nodes.txt` exists | `LabValidate.bash` |
| B | It contains the correct count, and nothing else | `LabValidate.bash` |

The grader recomputes the count from the cluster at validation time rather than
trusting a recorded number, so a node that changed state between setup and
validate is handled correctly.

## Gotchas

- **Ready and schedulable are different things.** The control-plane node is
  usually `Ready` — it is running the API server — but it carries the
  `NoSchedule` taint precisely so that ordinary workload never lands on it.
  Counting "the nodes that say Ready" gives the wrong answer; the task asks for
  the nodes that are Ready *and* not the control plane.

- **`Unknown` is not `Ready`.** `kubectl get nodes` shows the Ready column as
  `True`, `False` or `Unknown`. `Unknown` means the kubelet's heartbeat has
  stopped, and it is not a Ready node.

- **`Ready` is not the same as `Schedulable`.** The `kubectl get nodes`
  `SCHEDULING` column is a separate concept (it reflects the node's
  `.spec.unschedulable` flag), and it does not know about taints at all. A
  tainted node still shows `Scheduling` as enabled.

- **The file must hold the number and nothing else.** A file containing
  `2 nodes` is not a file containing `2`. Write the bare number.

- **The count can be zero.** On a single-node cluster the answer really is 0,
  and that is a correct answer rather than a failure.

## Environment requirements

- A cluster with at least two nodes for the question to be meaningful. On a
  plain single-node minikube the answer is 0.
- Write access to `/root` — the answer file lives there, so the validator has to
  run as a user who can read it.
