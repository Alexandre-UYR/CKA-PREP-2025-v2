# w12 — Three ways of asking to be put somewhere: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `place` | `LabSetUp.bash` | The three Pods live here and the task names the namespace. It is recreated on every run, so the pre-state is always the same. |
| 2 | A node labelled `workload=general` | `LabSetUp.bash` — `kubectl label node` | The node all three Pods have to end up on. The label is the only handle on it: the node's *name* differs from one cluster to the next, and a manifest with a name written into it would not survive being moved to another cluster. |
| 3 | Exactly one node carries that label | `LabSetUp.bash` | If two nodes carried `workload=general` the selector would match both, and "the node labelled workload=general" would not identify anything. |
| 4 | A control-plane node labelled `node-role.kubernetes.io/control-plane` | `LabSetUp.bash` | The other kind of node in the cluster, so that "the node labelled workload=general" is a real distinction and not the only node there is. |
| 5 | The target node is Ready and has no `NoSchedule` taint | the cluster | A `nodeSelector` and a pod affinity both go through the scheduler, which refuses nodes that are cordoned or carry an untolerated taint. A control-plane node normally carries `node-role.kubernetes.io/control-plane:NoSchedule`, so the target has to be a worker. |
| 6 | The target node's name recorded in `/tmp/cka-lab/w12.node` | `LabSetUp.bash` | A convenience for the candidate and a record for the setup. The validator does not use it: the validator looks the node up by its label, live, so it is correct on any cluster. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | Pod `pinned` exists in namespace `place` and is Running | `LabValidate.bash` |
| B | `pinned`'s `.spec.nodeName` is the node labelled `workload=general` | `LabValidate.bash` |
| C | Pod `selected` exists in namespace `place` and is Running | `LabValidate.bash` |
| D | `selected`'s `.spec.nodeSelector` has the key `workload` with the value `general` | `LabValidate.bash` |
| E | `selected` carries the pod label `app=selected` | `LabValidate.bash` |
| F | `selected`'s `.spec.nodeName` is the node labelled `workload=general` | `LabValidate.bash` |
| G | Pod `together` exists in namespace `place` and is Running | `LabValidate.bash` |
| H | `together`'s `.spec.affinity.podAffinity.requiredDuringSchedulingIgnoredDuringExecution` has a `labelSelector` that matches `app=selected` and a `topologyKey` of `kubernetes.io/hostname` | `LabValidate.bash` |
| I | `together`'s `.spec.nodeName` is the node labelled `workload=general` | `LabValidate.bash` |

## Gotchas

- **`nodeName` bypasses the scheduler entirely.** The kubelet is told which
  node to run the Pod on and runs it there, even if the node is out of room,
  even if the node has taints it does not tolerate, even if the node is
  cordoned. Nothing checks anything. That is why `pinned` lands where it is
  told to, and also why it can land somewhere broken.

- **`nodeSelector` and affinity go through the scheduler.** They respect
  taints, resource limits and readiness — and they need a node that actually
  matches. A `nodeSelector` for a label no node carries leaves the Pod
  Pending forever, with the reason in `kubectl describe pod`.

- **Pod affinity is a statement about OTHER pods, not about the node.** The
  selector in a `podAffinity` matches the *labels of pods*, and the
  `topologyKey` says what "the same place" means — `kubernetes.io/hostname`
  means the same node. So `together` is not asking for the node labelled
  `workload=general`; it is asking to be where `selected` already is. The
  two Pods have to be in the same namespace, because that is the scope the
  selector is evaluated in.

- **Affinity needs something to be attracted to.** If `selected` has not been
  created yet, or is not Running, or does not carry the label the selector
  asks for, `together` stays Pending with "didn't match pod affinity rules"
  in its events. Create `selected` first.

- **The Pod label and the affinity selector are two different things.**
  `selected`'s *pod* label `app=selected` is what `together`'s `labelSelector`
  matches against. A `nodeSelector` inside the affinity block would be a
  different mechanism entirely.

- **`matchLabels` and `matchExpressions` are both valid** ways of writing the
  label selector, and the validator accepts either.

- **A node's name is not portable; its labels are.** The task says to find
  the node by its label. A manifest with `nodeName: node-1` written by hand
  is wrong twice over: it is the wrong node on any other cluster, and it does
  not show that you understood how the node is identified.

- **The control-plane node is a trap, not a target.** It carries
  `node-role.kubernetes.io/control-plane:NoSchedule`, so a Pod that goes
  through the scheduler will not be placed there unless it tolerates that
  taint. `nodeName` would put it there regardless — and the grader would
  notice that it is not the node labelled `workload=general`.

## Environment requirements

- A cluster with at least two nodes: one worker to be the target, and a
  control-plane node to be the other one.
- The target worker node must be Ready and free of `NoSchedule` taints, or
  the `nodeSelector` and affinity Pods will never start.
- Registry access for `nginx:1.25`, so the Pods can actually run and reach
  the Running phase.
- No special components. This is plain scheduler behaviour.
