# c17 — Gateway API basics: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `default` | the cluster itself | The Deployment and the Service the route points at live here. It exists in every cluster, so the setup only re-applies it. |
| 2 | Deployment `web` in `default` - image `nginx`, 1 replica, labels `app=web` | `LabSetUp.bash` | The Service selects these pods. The HTTPRoute's backendRef names the Service, so the Service has to have something behind it for the route to be meaningful. |
| 3 | Service `web` in `default` - port 80, selector `app=web` | `LabSetUp.bash` | This is the backend the HTTPRoute forwards to. The task fixes the target name (`web`) and port (80), so the pre-state has to provide exactly that. |
| 4 | The Gateway API CRDs are **not** installed | `LabSetUp.bash` leaves them absent | Installing the CRDs is step 1 of the task. Without `gateways.gateway.networking.k8s.io` there is no `Gateway` resource type, and without `httproutes.gateway.networking.k8s.io` there is no `HTTPRoute` resource type. |
| 5 | A cluster with API server access to `github.com` (or a local copy of the CRD bundle) | the environment | The CRDs are installed from a release manifest, so the setup and the candidate both need to fetch it once. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | The CRD `gateways.gateway.networking.k8s.io` installed | `LabValidate.bash` |
| B | The CRD `httproutes.gateway.networking.k8s.io` installed | `LabValidate.bash` |
| C | A Gateway named `edge`, in any namespace | `LabValidate.bash` |
| D | That Gateway's `.spec.gatewayClassName` is `nginx` | `LabValidate.bash` |
| E | That Gateway has a listener with `protocol: HTTP` | `LabValidate.bash` |
| F | That Gateway has a listener with `port: 80` | `LabValidate.bash` |
| G | An HTTPRoute named `edge-route`, in any namespace | `LabValidate.bash` |
| H | Its `.spec.hostnames` contains `app.example.com` | `LabValidate.bash` |
| I | Its `.spec.parentRefs` contains a reference to a Gateway named `edge` | `LabValidate.bash` |
| J | One of its rules has a `backendRefs` entry naming `web` | `LabValidate.bash` |
| K | That `backendRefs` entry targets port `80` | `LabValidate.bash` |
| L | The pre-state Service `web` still exposes port 80 | `LabValidate.bash` |

## Gotchas

- **The CRDs are cluster-scoped, and so is the damage.** Deleting a CRD does not
  just remove the resource type - it deletes every object of that kind in the
  cluster. The reset therefore never removes the Gateway API CRDs. They are
  left in place and the setup re-applies the standard set idempotently when
  they are already present, so the environment is always in the same
  configuration. What the reset *does* remove is the candidate's Gateways and
  HTTPRoutes, which are namespaced and ordinary to delete.

- **The CRDs are not the same thing as a controller.** Installing the CRDs
  gives you the API types. It does not give you anything that programs a
  Gateway, so `gatewayClassName: nginx` will point at a GatewayClass that does
  not exist, and the Gateway's status will never become Programmed. The task
  says no controller is required, and the grader looks at the spec, not the
  status.

- **`spec.listeners[].protocol` is a case-sensitive enum.** `HTTP` is the
  value; `http` and `Http` are rejected by the API server, and `HTTPS` is a
  different protocol that would not satisfy the task.

- **The listener port is not the Service port.** They are the same number
  here, but they mean different things: the listener port is the port the
  Gateway accepts connections on, the backendRef port is the port on the
  Service the traffic is forwarded to. Both have to be 80.

- **`backendRefs[].name` is namespace-local.** A backendRef without an
  explicit `namespace` field refers to a Service in the *same namespace as the
  HTTPRoute*, not in the namespace where the Service happens to live. Putting
  the HTTPRoute in a namespace that has no Service `web` produces a route that
  can never resolve its backend.

- **The Gateway and the HTTPRoute do not have to share a namespace.** Gateway
  API supports cross-namespace attachment, and the grader searches every
  namespace for both objects.

## Environment requirements

- A cluster with at least one node.
- API server able to reach `github.com` so the Gateway API release manifest can
  be fetched (`https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml`).
- No gateway controller needed - do not install one, it is not part of the
  task.
- Registry access for `nginx` so the pre-state Deployment can run.
