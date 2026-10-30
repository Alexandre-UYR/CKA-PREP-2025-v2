# c8 — Place a Pod on a specific node: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `scheduling` | `LabSetUp.bash` | The task places both Pods in this namespace. It has to exist before a Pod can be created in it. |
| 2 | Exactly one node labelled `workload=general` | `LabSetUp.bash` | The task refers to the node by that label, not by name. The label is what the candidate looks up to find out where the Pods have to go. |
| 3 | That node is Ready, schedulable and is not a control-plane node | `LabSetUp.bash` picks it | A Pod can only become Running on a node that is Ready and not cordoned. A control-plane node usually carries a `NoSchedule` taint, which is exactly the sort of thing this question is about, so the labelled node is a worker. |
| 4 | A cluster with at least one worker node | the cluster itself | The question needs a node to pin to. On a single control-plane-only cluster there is nothing to label, and the setup stops with an error rather than building a broken environment. |
| 5 | The node name written to `/tmp/cka-lab/c8.node` | `LabSetUp.bash` | The validator never hard-codes a node name. This file is only a fallback for the case where the candidate removed the label again, and the reset uses it to find the node to clean up. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | A Pod named `pinned` in namespace `scheduling` | `LabValidate.bash` |
| B | `pinned` has `spec.nodeName` set to the node labelled `workload=general` | `LabValidate.bash` |
| C | A Pod named `selected` in namespace `scheduling` | `LabValidate.bash` |
| D | `selected` has a `nodeSelector` with the key `workload` and the value `general` | `LabValidate.bash` |
| E | `selected` ended up on that same node | `LabValidate.bash` |
| F | Both Pods are `Running` | `LabValidate.bash` |

## The difference the question is about

`nodeName` and `nodeSelector` look like two ways of writing the same thing.
They are not.

**`nodeName` bypasses the scheduler entirely.** The scheduler never sees the
Pod: the API server writes `spec.nodeName`, and the kubelet on that node
starts it. `NoSchedule` taints are therefore not enforced - they are only
ever enforced by the scheduler - and neither are resource limits. The kubelet
runs the Pod even if the node has no room for it, and the Pod ends up running
alongside whatever is already there. (A `NoExecute` taint is a different
matter: that one is the kubelet's business, and the kubelet does honour it.)

**`nodeSelector` goes through the scheduler.** It is an ordinary scheduling
requirement: the scheduler filters out every node that does not carry
`workload=general`, and then places the Pod on one of the survivors like any
other. Taints are respected (unless the Pod has a matching toleration),
resource limits are respected, and if nothing matches the Pod stays `Pending`
forever with the reason in its events.

That is why the task asks for two Pods rather than one: it wants both
mechanisms side by side, and the validator checks that the `nodeSelector` Pod
actually landed on the labelled node, which it can only do by going through
the scheduler.

## Gotchas

- **The label is the only handle on the node.** The task never gives you a node
  name, and it should not: node names change between clusters. Look the node
  up with `kubectl get nodes -l workload=general -o jsonpath='{.items[0].metadata.name}'`
  and use that value in the manifest.

- **`kubectl run` cannot set `nodeName`.** It has no flag for it. Write the
  Pod out as YAML, or use `--overrides='{"spec":{"nodeName":"..."}}'`.

- **`kubectl run` can set a `nodeSelector`.** `--overrides='{"spec":{"nodeSelector":{"workload":"general"}}}'`
  works, and so does `kubectl label node <node> workload=general` plus a
  `nodeSelector` in a manifest.

- **A Pod with `nodeName` is not scheduled, so it is not evicted.** If you set
  `nodeName` to a node name that does not exist, the Pod stays `Pending` with
  no useful event, because nothing ever tries to place it.

- **`nodeSelector` needs an exact match.** `workload=general` does not match
  `workload=General`; label values are case-sensitive.

- **Labels on nodes are not part of the Pod spec.** If you label a node and
  then create a Pod with a `nodeSelector` for a label that does not exist,
  the Pod is not rejected - it is simply never scheduled, and `kubectl describe`
  shows `0/1 nodes are available`.

- **Both Pods need an image.** The task does not name one; any small image
  that the cluster can pull works.

## Environment requirements

- A cluster with at least one Ready, schedulable worker node.
- Registry access for a small image such as `nginx` or `busybox`, for the two
  Pods to become `Running`.
- No special components. Plain Pods with no networking requirements are
  enough.
