# c13 — Ingress with several rules: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `ingress` | `LabSetUp.bash` | The Ingress and everything it routes to live in it. |
| 2 | Deployment `app-a`, labels `app=a`, image `nginx:1.25`, 1 replica, container port 80 | `LabSetUp.bash` | It is what Service `app-a` selects and what the `/a` and `/` paths are routed to. The label has to be on the **pod template**, not only on the Deployment, or the Service selects nothing. |
| 3 | Deployment `app-b`, labels `app=b`, image `nginx:1.25`, 1 replica, container port 80 | `LabSetUp.bash` | It is what Service `app-b` selects and what the `/b` path is routed to. |
| 4 | Service `app-a`, port 80, selector `app: a` | `LabSetUp.bash` | The Ingress backend names a Service, not a Deployment. The Ingress refers to `app-a` by name and by the Service's port 80, so the Service has to exist and has to expose that port. |
| 5 | Service `app-b`, port 80, selector `app: b` | `LabSetUp.bash` | Same, for the `/b` path. |
| 6 | A cluster with a working scheduler and a node that can run `nginx:1.25` | the cluster itself | The Deployments have to be running for the Services to have endpoints, so the pre-state is a working cluster rather than a set of objects pointing at nothing. |

**No ingress controller is required.** The Ingress object is created and
graded by reading the API. A controller is only needed for the traffic to
actually arrive, and this question does not ask for that.

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | Ingress `web` in namespace `ingress` | `LabValidate.bash` |
| B | `spec.ingressClassName` is `nginx` | `LabValidate.bash` |
| C | A rule whose host is `shop.example.com` | `LabValidate.bash` |
| D | That rule has a path `/a` with `pathType: Prefix` | `LabValidate.bash` |
| E | Path `/a` is routed to Service `app-a`, port 80 | `LabValidate.bash` |
| F | That rule has a path `/b` with `pathType: Prefix` | `LabValidate.bash` |
| G | Path `/b` is routed to Service `app-b`, port 80 | `LabValidate.bash` |
| H | A second rule whose host is `api.example.com` | `LabValidate.bash` |
| I | That rule has a path `/` with `pathType: Prefix` | `LabValidate.bash` |
| J | Path `/` is routed to Service `app-a`, port 80 | `LabValidate.bash` |

## Gotchas

- **`pathType` is required in `networking.k8s.io/v1`.** A path without it is
  rejected by the API server:
  `spec.rules[0].http.paths[0].pathType: Required value`. The three values
  are `Exact`, `Prefix` and `ImplementationSpecific`, and they are spelled
  exactly that way. `Prefix` also has to be capitalised — `prefix` is
  rejected too.

- **The backend is a Service, not a Deployment.** The Ingress names
  `app-a`, and `app-a` is a Service in this namespace. A backend that names a
  Deployment works only if a Service of the same name also exists, because
  the Ingress controller forwards to the Service's endpoints.

- **The port is the Service's port.** `port.number: 80` is the port the
  client connects to on the Service. It is not the container port, and it
  does not have to be the same number — here both happen to be 80.

- **A host with no matching path still falls through to the `/` prefix rule
  of the same host.** That is what keeps `shop.example.com` and
  `api.example.com` separate: a request to `shop.example.com/anything` does
  not reach the `api.example.com` rule, it is matched against
  `shop.example.com`'s own rules, and if none of them match, against
  `shop.example.com`'s `/` prefix rule — which this question does not
  define, so such a request gets a 404. Giving the `api.example.com` rule a
  `/` prefix path is what makes that host work for everything under it.

- **Several paths in one rule is one `paths:` list, not several rules.** The
  rule is the host; the paths under it share it. Two rules with the same
  host is not the way to do it.

- **`ingressClassName` is what tells the controller which one to use.** The
  class named `nginx` does not have to exist for the Ingress to be created
  — the API server does not check it — but without a controller watching that
  class, nothing serves the object. An older annotation,
  `kubernetes.io/ingress.class`, does the same job; the field is the modern
  one.

- **The Ingress object is not the traffic.** `kubectl get ingress` shows the
  object, not the routes. With no controller installed there is no
  `ADDRESS` and nothing answers on it.

## Environment requirements

- A cluster with at least one node and a working scheduler.
- Registry access for `nginx:1.25`.
- Permission to create Ingresses and to read Deployments and Services in
  namespace `ingress`.
- **No ingress controller is required** — neither to create the Ingress nor
  to grade it. If you want to try the traffic for real, install a controller
  configured for class `nginx`, and point `shop.example.com` and
  `api.example.com` at the controller's address in `/etc/hosts`.
