# c3 — Service on a named port: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `namedport` | `LabSetUp.bash` | The Deployment and the Service both live here, and every command is namespaced to it. |
| 2 | Deployment `web`, image `nginx:1.25`, 1 replica, labels `app=web` | `LabSetUp.bash` | The Service needs pods to select. A Deployment rather than a bare Pod, so the labels are stable and the pods are managed. |
| 3 | The container of `web` declares **no ports at all** | `LabSetUp.bash` | This is the point of the question. A named `targetPort` is resolved against the pod's *named container ports*, so with no named port the Service can be created, will look correct, and will have no endpoints. The candidate has to add the name first. |
| 4 | A cluster with a working scheduler and a node that can run `nginx:1.25` | the cluster itself | The pod has to be running before the Service can have endpoints. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | A `containerPort` named `http`, port 80, protocol TCP, in the container of Deployment `web` | `LabValidate.bash` |
| B | Service `web-svc` in namespace `namedport` | `LabValidate.bash` |
| C | Service type `ClusterIP` | `LabValidate.bash` |
| D | Service port named `http`, port 80, protocol TCP | `LabValidate.bash` |
| E | Service `targetPort` is the string `http`, not the number `80` | `LabValidate.bash` |
| F | The Service selects the pods: at least one endpoint address, resolving to port 80 | `LabValidate.bash` (live check) |

## Gotchas

- **A named `targetPort` refers to the container port's NAME.** If the
  container has no named port, the Service object still looks perfectly
  right - `kubectl get svc` shows `http 80/TCP` - but it silently gets no
  endpoints, because there is nothing for the name to resolve to. This is
  the failure this question is built around, and it is why the grader
  checks the endpoints and not just the Service object.

- **`targetPort: http` and `targetPort: 80` are different objects.** The
  first is a string, the second is a number, and `kubectl get svc` prints
  them the same way. The question asks for the name, so that the Service
  keeps working if the container port moves. Check it with
  `-o jsonpath='{.spec.ports[0].targetPort}'` and read the quotes.

- **The container port has to exist and be named.** `containerPort` is
  documentation for humans in the sense that nothing is actually bound to
  it - the port is reachable whether or not it is declared. What the
  declaration buys you is a *name*, and the name is what the Service's
  `targetPort` is matched against.

- **Port names have rules.** A `containerPort` name must be an IANA service
  name: at most 15 characters, lower case alphanumeric with dashes, and it
  must contain at least one letter. `http` is fine; `HTTP` and `http-port`
  are also fine, but `80` is not a legal name.

- **The Service needs a selector that matches the pod labels.** The
  pre-state labels the pods `app=web`, so the Service selector has to match
  that, or it selects nothing and again ends up with no endpoints. A
  Service with no selector at all is legal, but then you have to populate
  the Endpoints object by hand.

- **Endpoints need ready pods.** The Endpoint controller only adds an
  address for a pod that is ready. If the pod is still pulling `nginx` or
  failing its readiness probe, the Service has no endpoints even though
  everything in the YAML is right. Wait for the rollout before you judge.

- **Protocol is defaulted, but check it anyway.** `protocol` defaults to
  `TCP` on both the container port and the Service port, so an omitted
  protocol is not an error. The grader checks the value either way.

## Environment requirements

- A cluster with at least one node and a working scheduler.
- Registry access for `nginx:1.25`.
- The Endpoint controller - part of kube-controller-manager in every normal
  cluster - so that the Service gets an Endpoints object.
- Nothing else. A ClusterIP Service needs no ingress controller, no
  LoadBalancer and no DNS plugin beyond the in-cluster one.
