# w11 — Bring the nodes back: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | A cluster with at least two nodes | the cluster | The question is about two different nodes refusing pods for two different reasons. With one node the pre-state collapses and the two fixes land on the same object. |
| 2 | One node cordoned — `.spec.unschedulable=true` | `LabSetUp.bash` — `kubectl cordon` | The first half of the broken state. It shows up in `kubectl get nodes` as `SchedulingDisabled` in the STATUS column, and it is a flag on the node, not a taint. |
| 3 | Another node tainted `dedicated=payments:NoSchedule` | `LabSetUp.bash` — `kubectl taint` | The second half of the broken state. A taint is a property ordinary pods have to actively tolerate, and `NoSchedule` keeps new pods away without evicting anything. |
| 4 | The two nodes recorded in `/tmp/cka-lab/w11.nodes` | `LabSetUp.bash` | The setup writes `CORDONED=<node>` and `TAINTED=<node>`. Once the taint is gone the cluster no longer says which node it was, and the validator needs that to check the label landed on the right node. |
| 5 | No node carrying `dedicated=payments:NoSchedule` before the setup runs | `LabSetUp.bash` | The setup removes the taint from every node first, so a second run starts from the same state as the first and the taint is the lab's, not the cluster's. |
| 6 | No node labelled `Status=VIP` before the setup runs | `LabSetUp.bash` | The setup clears the label from every node first. Otherwise a leftover label from a previous attempt would make "exactly one node carries it" pass for the wrong reason. |
| 7 | The cluster's own control-plane taint left in place | the environment | A kubeadm control-plane node normally carries `node-role.kubernetes.io/control-plane:NoSchedule`. It is not the lab's business and the reset must not remove it. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | The cordoned node is schedulable again — `.spec.unschedulable` is false or absent | `LabValidate.bash` |
| B | No node in the cluster carries the `dedicated=payments` taint | `LabValidate.bash` |
| C | Exactly one node carries the label `Status=VIP` | `LabValidate.bash` |
| D | ... and it is the node that carried the taint | `LabValidate.bash` |
| E | `kubectl get nodes -l Status=VIP` returns exactly one line | `LabValidate.bash` |

The node names are read live from the cluster and from the setup's state
file; nothing about the cluster is hard-coded in the validator, so the same
validator is correct on any cluster.

## Gotchas

- **Cordoning and tainting are different things.** `unschedulable` is a flag
  on the node — `kubectl cordon` sets it and `kubectl uncordon` clears it.
  The scheduler honours it for **new** pods, and it evicts nothing: whatever
  is already running on that node keeps running. A taint is a property of the
  node that ordinary pods must actively tolerate, and `NoSchedule` also keeps
  new pods away without evicting anything. The two look similar from the
  outside and are fixed with different commands.

- **Draining is a third thing, and it does evict.** `kubectl drain` moves
  pods off the node — it respects the eviction API and waits for the
  workloads to go. The task does not ask for a drain: the node's problem is
  that it will not take new pods, and the fix is to let it take them again.

- **Removing a taint means removing exactly that taint.** The syntax carries a
  trailing minus: `kubectl taint node <node> dedicated=payments:NoSchedule-`.
  Without the minus you *add* a taint. And a control-plane node usually
  carries its own taint as well — that one belongs to the cluster, not to
  this question, and it must be left alone.

- **`kubectl uncordon` is the counterpart of `kubectl cordon`,** and it works
  on a node that was never cordoned too, which makes it safe to run.

- **A label is not a taint and does not affect scheduling.** `Status=VIP` is
  only a piece of metadata the candidate is attaching so that it can be
  selected on. It changes nothing about where pods go, and that is the point
  of the last step: a label that a selector can find is a label that is
  useful.

- **Label keys and values may contain capitals.** `Status=VIP` is a legal
  label, and `kubectl get nodes -l Status=VIP` finds it. The rule is that
  the key must start and end with an alphanumeric character and may contain
  dashes, underscores and dots in between.

- **`kubectl get nodes -l <selector>` returns one line per node,** so it is
  the check that proves the label is usable rather than merely present. If it
  returns nothing, the label was never applied; if it returns two lines,
  something else in the cluster already carried it.

## Environment requirements

- A cluster with at least **two** nodes, and at least one node that is Ready
  and is not the control-plane, so that the pre-state can be built from two
  distinct nodes.
- No special components. This is ordinary node metadata: `kubectl cordon`,
  `kubectl uncordon`, `kubectl taint`, `kubectl label`.
- The validator needs the setup's state file, `/tmp/cka-lab/w11.nodes`, to
  know which node was which. The reset removes it, and the setup recreates
  it.
