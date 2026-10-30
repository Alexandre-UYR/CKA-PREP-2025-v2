# Q10 — Taints & Tolerations: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | A running cluster with at least one schedulable node | the playground itself | Both halves of the task are about scheduling: you taint a node and then place a pod on it. There has to be a node. |
| 2 | A node called `node01` | the KillerCoda playground (it is `minikube` on a local cluster) | The task names `node01` specifically. The validator falls back to the first node if `node01` does not exist, and prints which node it used. |
| 3 | Enough spare capacity on that node for one more pod | the playground itself | The pod that tolerates the taint has to actually be scheduled there. A node at capacity leaves the pod `Pending` for a reason that has nothing to do with the taint. |
| 4 | A record of the cluster's nodes | `LabSetUp.bash`, into `/tmp/cka-lab/q10.nodes` | The reset removes the `PERMISSION` taint from **every** node, because the candidate may have tainted a different one from the one the setup saw. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | The taint `PERMISSION=granted:NoSchedule` on a node | `LabValidate.bash` |
| B | A pod running on that node | `LabValidate.bash` |
| C | That pod carries a toleration for key `PERMISSION` with effect `NoSchedule` | `LabValidate.bash` |
| D | No *other* ordinary pod got scheduled onto the tainted node | `LabValidate.bash` |

## Gotchas

- **A DaemonSet pod is not an answer.** DaemonSets tolerate every taint
  automatically, so a pod that is running on the tainted node but is managed by
  a DaemonSet proves nothing. The validator excludes DaemonSet-owned pods and
  pods in `kube-system` for exactly this reason.

- **`NoSchedule` is not `NoExecute`.** `NoSchedule` keeps new pods off the node
  but does not evict anything already running on it. `NoExecute` would evict
  running pods that do not tolerate the taint. The task asks for `NoSchedule`.

- **A toleration with no `value` tolerates any value.** `tolerations: [{key: PERMISSION, operator: Exists, effect: NoSchedule}]` is a valid and common answer. The validator accepts it, but does report when the pod's toleration carries no `granted` value, because matching the value exactly is the more precise answer.

- **The taint key is `PERMISSION`, uppercase.** Taint keys are namespaced by convention and the task uses a capitalised one. `permission` is a different key and will not match.

- **Taints and labels are different mechanisms.** A `nodeSelector` or
  `nodeAffinity` term on the pod is not a toleration; the scheduler will still
  refuse to place the pod. The task needs both halves: the toleration (to be
  allowed there) and a placement rule (to want to go there).

## Environment requirements

- A cluster with at least one node and a working scheduler. Nothing else is
  needed — this question has no extra components.
- The `kubectl` context must be the cluster you are practising on.
