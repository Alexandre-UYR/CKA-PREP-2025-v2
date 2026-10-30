# c9 — Spread pods across nodes: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `topology` | `LabSetUp.bash` | The task names the namespace, so it has to exist before the Deployment can be patched. |
| 2 | Deployment `spread` with 4 replicas, image `nginx:1.25`, `app=spread` on the pod template | `LabSetUp.bash` | This is the object the constraint is added to and the thing that is scaled. It has to be there, and it has to have labels, because the constraint's `labelSelector` works on labels. |
| 3 | The Deployment has **no** `topologySpreadConstraints` | `LabSetUp.bash` recreates it | The candidate adds the constraint. If the setup left one behind, the task would be half done before it starts. The setup deletes and recreates the Deployment on every run, so the pre-state is the same however the last attempt ended. |
| 4 | All 4 replicas are ready | `LabSetUp.bash` waits for the rollout | The pods that already exist are the ones the scheduler counts when it places the new ones. Starting from a steady state is what makes the spread observable. |
| 5 | A cluster with at least two nodes | the cluster itself | A spread over one node is not a spread. The setup warns when there is only one node, and the validator skips the spread check in that case. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | A `topologySpreadConstraints` entry in the Deployment's **pod template** (`spec.template.spec`) | `LabValidate.bash` |
| B | `maxSkew: 1` | `LabValidate.bash` |
| C | `topologyKey: kubernetes.io/hostname` | `LabValidate.bash` |
| D | `whenUnsatisfiable: ScheduleAnyway` | `LabValidate.bash` |
| E | A `labelSelector` that matches `app=spread` | `LabValidate.bash` |
| F | `spec.replicas: 8` | `LabValidate.bash` |
| G | 8 ready replicas | `LabValidate.bash` |
| H | The running pods on at least two different `spec.nodeName` values | `LabValidate.bash` |

## The difference `whenUnsatisfiable` makes

`ScheduleAnyway` tells the scheduler to *prefer* an even spread but never to
refuse a placement. The scheduler looks for the domain with fewer matching
pods; if the rule cannot be satisfied it places the pod anyway and moves on.
That is why a single-node cluster still works: with one domain there is no
skew to speak of, and every pod is placed.

`DoNotSchedule` is a hard rule. The scheduler refuses any placement that
would push the skew past `maxSkew`, and a refused pod stays `Pending` until
the situation changes on its own. On a two-node cluster, scaling this
Deployment from 4 to 8 with `DoNotSchedule` can leave the new pods `Pending`
forever: the four pods that already exist are not spread evenly, and the
scheduler is not allowed to add to the busy node to fix it, so it has nowhere
to put the new ones. `ScheduleAnyway` is the safe choice, and it is what the
task asks for.

## Gotchas

- **The constraint belongs to the pod template, not to the Deployment.** It
  goes in `spec.template.spec.topologySpreadConstraints`. A constraint placed
  on `spec` itself is not a valid field and the API server will reject the
  whole object.

- **A constraint only affects pods scheduled after it exists.** The four pods
  that are already running were placed before the constraint was added, and
  they do not move. Only the new pods are spread.

- **The `labelSelector` has to match the pod template's labels.** The
  constraint counts the pods that the selector matches. A selector for
  `app=other` matches nothing, so every domain looks empty, the skew is
  always zero, and nothing is ever spread. `matchLabels: {app: spread}` is
  what the task asks for; a `matchExpressions` entry on the same key works
  just as well.

- **`maxSkew` is a number, not a string.** `maxSkew: "1"` is rejected.

- **`topologyKey` is a node label.** `kubernetes.io/hostname` is set on every
  node by the kubelet and is the usual way to spread over nodes. A key that no
  node carries puts every pod in a single empty domain, which spreads nothing.

- **The scheduler does not move pods.** Scaling a Deployment up creates new
  pods; it never reschedules the old ones. To see a fresh spread, delete the
  pods and let the Deployment recreate them.

## Environment requirements

- A cluster with at least two nodes for the spread to be visible. On one node
  the lab still runs, but the spread check is skipped.
- Registry access for `nginx:1.25`.
- No special components: `topologySpreadConstraints` is handled by the
  scheduler that is already there.
