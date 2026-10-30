# x15 — The Service that selects nothing: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `shop` | `LabSetUp.bash` | The Deployment and the Service live here, and the task names the namespace. |
| 2 | Deployment `cart` — `nginx:1.25`, 2 replicas, pods labelled `app=cart-v2` | `LabSetUp.bash` | The workload that is running perfectly well. The pods carry `app=cart-v2`, and the task insists they keep it. |
| 3 | Service `cart-svc` — ClusterIP, port 80 -> targetPort 80, selector `app=cart` | `LabSetUp.bash` | The broken object. Its selector says `app=cart`; the pods say `app=cart-v2`, so it selects nothing and has no endpoints. |
| 4 | The Service's UID recorded | `LabSetUp.bash`, into `/tmp/cka-lab/x15.svc.uid` | The task forbids deleting and re-creating the Service. The grader compares the UID at validate time with the one recorded here. |
| 5 | The pods to actually be Running and Ready | `LabSetUp.bash` waits for the rollout | The pre-state has to be the broken state. If the pods were not up, "no endpoints" would have a second, more obvious cause. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | The Service `cart-svc` still there, with the UID recorded at setup — edited in place | `LabValidate.bash` |
| B | Its selector now matches the labels the pods carry | `LabValidate.bash` |
| C | The pods still labelled `app=cart-v2` | `LabValidate.bash` |
| D | The Service has at least 2 endpoint addresses | `LabValidate.bash` |
| E | The Deployment `cart` still has 2 ready replicas | `LabValidate.bash` |

## Gotchas

- **A Service with a selector that matches nothing is a perfectly valid
  object.** It simply has no endpoints, and nothing errors: the API server
  accepts it, the Service controller creates an Endpoints object with no
  addresses, and `kubectl get pods` looks healthy. There is no event and no
  message to read — the only evidence is the empty `ENDPOINTS` column.

- **The mismatch between what the Service selects on and what the pods carry
  is the whole failure.** There are two ways out: change the Service's
  selector, or change the pods' labels. The task rules the second one out on
  purpose, because something else selects on `app=cart-v2`. So the Service is
  what has to change.

- **"Edit the Service" means edit it, not replace it.** `kubectl patch svc`
  changes the object in place and keeps its UID. `kubectl delete` plus
  `kubectl create` produces a Service that works and looks identical — and
  the UID check catches it.

- **Relabelling the pods is not as easy as it looks.** Changing a Deployment's
  template labels changes its selector too, and the two have to keep
  agreeing; changing the labels of running pods directly is not a field the
  API server lets you set. Either way the task forbids it.

- **A Service with no selector at all is not the answer.** It would pick up
  every pod in the namespace, and it would not be "selecting the pods that
  are there" by label. The grader wants a selector that matches.

- **The Endpoints object is filled in by a controller.** After the selector
  is corrected the endpoints do not appear instantly; give them a second or
  two. Newer clusters also keep the addresses in EndpointSlices, so
  `kubectl get endpointslice -l kubernetes.io/service-name=cart-svc` is worth
  a look if the Endpoints object looks stale.

## Environment requirements

- A cluster with at least one node, and registry access for `nginx:1.25`.
- No special components. This is plain Service, Endpoints and label
  selection behaviour.
