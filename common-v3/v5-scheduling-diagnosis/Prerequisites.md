# v5 — The pod that has been Pending for ten minutes: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `sched` | `LabSetUp.bash` | The Pod lives here and the task names the namespace. |
| 2 | Pod `stuck`, labels `app=stuck`, image `nginx:1.25` | `LabSetUp.bash` | The workload under investigation. It exists so the candidate diagnoses a running system instead of building one. |
| 3 | Pod `stuck` carries `nodeSelector: {disk: ssd}` | `LabSetUp.bash` | The first reason it cannot be placed: no node in the cluster carries the label `disk=ssd`. A Pod's nodeSelector is immutable, so this cannot be edited away in place. |
| 4 | Node A, labelled `disk=hdd`, cordoned (`.spec.unschedulable=true`) | `LabSetUp.bash` — `kubectl cordon` | The second reason. A cordoned node accepts no new pods, whatever they select. The candidate has to spot `Unschedulable: true` in `kubectl describe node`. |
| 5 | Node B, labelled `disk=nvme`, tainted `dedicated=db:NoSchedule` | `LabSetUp.bash` — `kubectl taint` | The third reason. The Pod carries no matching toleration, so the taint keeps the scheduler away from that node. |
| 6 | At least one node that is Ready and is neither cordoned nor tainted | The cluster | The candidate has to put the Pod somewhere. Without a viable target, the question has no answer. |
| 7 | The scheduler has already recorded a `FailedScheduling` event for `stuck` | `LabSetUp.bash` waits for it | The pre-state has to BE the broken state. The setup polls the Pod's events and warns if the verdict has not landed yet. |

The setup records which node is which in `${TMPDIR:-/tmp}/cka-v5-scheduling-diagnosis.env`
(`NODE_A`, `NODE_B`), and reports the same thing on stdout. The candidate is
expected to work the node names out of the cluster, not out of that file.

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | A Pod in namespace `sched` — the original `stuck` or a replacement | `LabValidate.bash` |
| B | That Pod's phase is `Running`, and its container is ready | `LabValidate.bash` |
| C | The Pod is scheduled — `.spec.nodeName` is set | `LabValidate.bash` |
| D | The node it landed on is `Ready` | `LabValidate.bash` |
| E | That node is not cordoned — `.spec.unschedulable` is not `true` | `LabValidate.bash` |
| F | That node carries no `NoSchedule` taint | `LabValidate.bash` |

The node checks are computed live from the cluster, not against a hard-coded
node name, so the same validator is correct on any cluster.

## Gotchas

- **`kubectl describe pod` is where the scheduler's verdict is written.** The
  Events section says exactly why: "didn't match Pod's node affinity/selector",
  "had untolerated taint", "was cordoned". Three different reasons produce
  three different fixes, and here all three are in play. A candidate who reads
  only `kubectl get pods` sees `Pending` and learns nothing.

- **The reasons are not all on the Pod.** Two of the three live on the nodes.
  `kubectl describe node <name>` shows `Unschedulable: true` for the cordoned
  node and the taint list for the tainted one.

- **Fixing only one reason is not enough.** The scheduler evaluates every
  predicate on a node. A node that matches the selector but is cordoned is
  still not a candidate, and a node that is schedulable but does not match
  the selector is still not a candidate. The fix has to hold on one single
  node.

- **A Pod's nodeSelector is immutable.** `kubectl edit pod stuck` will not
  change it. The candidate either gives a node the label the selector wants
  (`kubectl label node <node> disk=ssd`) or deletes and re-creates the Pod.

- **A cordon is a node field, a taint is a node field, and neither of them is
  in the Pod.** `.spec.unschedulable=true` is cleared with `kubectl uncordon`;
  a taint is cleared with `kubectl taint node <node> dedicated=db:NoSchedule-`
  (or worked around by giving the Pod a matching `toleration`).

- **`NoExecute` taints block as well.** The validator checks `NoSchedule`
  specifically, because that is what the task describes — but a `NoExecute`
  taint on the target node would keep the Pod Pending all the same.

- **A namespace does not own its nodes.** Deleting namespace `sched` does not
  un-cordon a node or remove a taint. That is why the reset script walks
  every node explicitly.

- **Watch out for the leftover original.** If the candidate re-creates the Pod
  under a different name and leaves the old `stuck` behind, the validator
  grades the Pod that is actually Running and says so.

## Environment requirements

- A cluster with at least **two worker nodes** is the intended environment: one
  gets cordoned, one gets tainted. With a single worker node the setup falls
  back to cordoning a control-plane node and keeps the taint on the worker, so
  the candidate's target is still the node with the single fixable taint. With
  a one-node cluster the same node carries both problems.
- A control-plane node normally carries its own
  `node-role.kubernetes.io/control-plane:NoSchedule` taint. If the candidate
  aims at such a node they have to clear that taint too; the intended target
  is the worker.
- Registry access for `nginx:1.25`, so the Pod can actually start once it is
  placed. `imagePullPolicy` is `IfNotPresent`.
- No special components: this is plain scheduler behaviour, `kubectl cordon`
  and `kubectl taint`.
