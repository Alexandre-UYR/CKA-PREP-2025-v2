# c6 — Taint and untaint: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `taints` | `LabSetUp.bash` | The task names the namespace the Deployment lives in. It has to exist before the Deployment can be patched in it. |
| 2 | Deployment `workload` in namespace `taints`: 1 replica, image `nginx`, pod template labelled `app=workload` | `LabSetUp.bash` | The task says to *patch* this Deployment, so it has to already exist — and it has to have a pod template, because the toleration and the placement rule both belong in the template, not on a running Pod. |
| 3 | A node carrying `dedicated=payments:NoSchedule` | `LabSetUp.bash` | This is the node the workload has to end up on. The taint is what makes the placement non-trivial: without a toleration, the scheduler will never put the pod there. |
| 4 | A *different* node carrying `do-not-use=true:NoSchedule` | `LabSetUp.bash` | This is the node the task asks you to clean up. It has to be a different node, otherwise "remove the do-not-use taint" and "make the pod schedulable on the payments node" would contradict each other. |
| 5 | A cluster with at least two nodes, at least one of them a worker | the cluster itself | The task moves a workload between two nodes, and the scheduler needs somewhere else to put the pod before the toleration exists. |
| 6 | The node names, written to `/tmp/cka-lab/c6.nodes` | `LabSetUp.bash` | The grader has to know which node carried which taint — "the node that carries it" is not something it can guess once the taints have changed. |
| 7 | The Deployment's UID, written to `/tmp/cka-lab/c6.uid` | `LabSetUp.bash` | The task says the Deployment must be patched, not re-created. A patched object keeps its UID; a re-created one gets a new one. That is how the constraint is graded. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | The `do-not-use` taint removed from every node | `LabValidate.bash` |
| B | The `dedicated=payments:NoSchedule` taint left in place on its node | `LabValidate.bash` |
| C | A toleration on the pod template with key `dedicated` and effect `NoSchedule` | `LabValidate.bash` |
| D | A placement rule on the pod template — a `nodeSelector` the node satisfies, or a `nodeAffinity` | `LabValidate.bash` |
| E | The workload's pod running, and `spec.nodeName` equal to the payments node | `LabValidate.bash` |
| F | The Deployment's UID unchanged (patched, not re-created) | `LabValidate.bash` |

## Why this pre-state is doing work

The interesting part of this question is that it asks for two different
mechanisms and both are necessary. A toleration and a placement rule do
different jobs:

- A **toleration** says "this pod is allowed on a node with this taint". It
  is a *permission*, not an instruction.
- A **nodeSelector** or **nodeAffinity** says "put this pod on *this* node".
  It is the *instruction*.

Without the toleration, the scheduler refuses to place the pod on the tainted
node. Without the placement rule, the scheduler is perfectly happy to place
it anywhere else that happens to be free — and the placement rule alone fails
too, because the taint still rejects the pod. **You need both**, and that is
exactly why the task asks for both and why the grader checks them
separately.

The pre-state puts the pod where it cannot schedule at all: both nodes in
play are tainted, and the pod template has neither a toleration nor a
placement rule. There is no such thing as a partially-right answer here.

## Gotchas

- **A toleration only says "I may go there"; it does not make the scheduler
  want to.** This is the single most common mistake in this question. A pod
  with a toleration for `dedicated=payments:NoSchedule` and nothing else can
  still land on any other node. The grader checks the toleration *and* the
  placement rule, and checks where the pod actually ended up.

- **`NoSchedule` does not evict pods that are already running.** It only
  stops *new* pods from being scheduled onto the node. So if a pod was
  already running on a node before the taint was applied, `NoSchedule` will
  not move it and `NoExecute` will not either until the pod is restarted.
  That is why the task is graded on the *pod template* rather than on the
  running pod: the template is what the scheduler reads when it creates the
  next pod.

- **`NoSchedule` and `NoExecute` are different effects.** `NoSchedule` is
  about new pods. `NoExecute` also evicts the pods that are already there.
  A toleration only tolerates a taint whose effect it matches: an empty
  effect tolerates every effect, but a toleration with effect `NoExecute`
  does **not** tolerate a `NoSchedule` taint, and a toleration with effect
  `NoSchedule` does not tolerate a `NoExecute` taint. The task names
  `NoSchedule`, so that is the effect the toleration needs.

- **The taint key and the toleration key must match, and so must the value.**
  The taint is `dedicated=payments:NoSchedule`, so the toleration needs key
  `dedicated`. Its value depends on the operator: `operator: Equal` with
  `value: payments` matches this taint, but `operator: Equal` with no value
  matches only a taint whose value is empty — which `dedicated=payments` is
  not. `operator: Exists` with the key and no value tolerates the taint
  whatever its value. The grader looks for key `dedicated` and effect
  `NoSchedule`.

- **`spec.nodeName` is not a placement rule.** Setting `nodeName` on the pod
  template does put the pod on the node, but it bypasses the scheduler
  entirely — the scheduler is not involved in any of its decisions, and the
  taint is not evaluated the same way. The task asks for a nodeSelector or a
  nodeAffinity, and the grader looks for one of those two.

- **A nodeSelector needs a label that the target node actually has.** The
  label every node has is `kubernetes.io/hostname`, whose value is the node's
  own name. `kubectl get nodes --show-labels` is how you find one.

- **Patch the Deployment, not the Pod.** `kubectl patch deployment` (or
  `kubectl edit deployment`) changes the pod template. Editing the running
  Pod is impossible — most of a Pod's spec fields are immutable — and it
  would be thrown away by the Deployment controller anyway.

- **Re-creating the Deployment breaks the task.** `kubectl delete` followed
  by `kubectl apply` gives you a working Deployment that fails the grader,
  because the UID changed. `kubectl apply` of an edited copy of the same
  Deployment keeps the UID and is the intended answer.

- **Removing a taint has its own syntax.** The trailing `-` removes it:
  `kubectl taint nodes <node> dedicated=payments:NoSchedule-`. A removal
  that names the wrong key or value is an error and the taint stays.

## Environment requirements

- A cluster with at least two nodes, at least one of which is a worker.
- Scheduler and controller-manager running normally.
- Registry access for `nginx:1.27`, so the workload's pod can actually start.
- `kubectl` configured with permission to patch Deployments and to taint
  nodes in the cluster.
