# Q11 — Gateway API: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | The Gateway API **standard** CRDs (`gateways.gateway.networking.k8s.io`, `gatewayclasses.gateway.networking.k8s.io`, `httproutes.gateway.networking.k8s.io`) at v1.5.0 | `LabSetUp.bash`, from the upstream `standard-install.yaml` release manifest | Without the CRDs there is no `Gateway` or `HTTPRoute` kind at all. The *standard* channel (not `experimental`) is the right one: the standard channel already has `Gateway`, `GatewayClass` and `HTTPRoute`, and it does not pull in the experimental-only `ReferenceGrant`/`BackendTLSPolicy`/`GRPCRoute` objects. |
| 2 | Deployment `web-deployment` (nginx, 2 replicas, labels `app=web`, container port 80) | `LabSetUp.bash` | The thing being exposed. Two replicas so the answer is not trivially a single pod, and so an Ingress/Gateway points at something that actually has endpoints. |
| 3 | Service `web-service` (port 80 -> targetPort 80, selector `app=web`) | `LabSetUp.bash` | The backend the Ingress routes to today, and the backend the HTTPRoute must route to tomorrow. The migration has to preserve the backend, not invent a new one. |
| 4 | TLS Secret `web-tls`, self-signed, **CN = `gateway.web.k8s.local`** | `LabSetUp.bash` (`openssl req -x509` piped into `kubectl create secret tls`) | The Ingress terminates TLS with this secret. The Gateway has to reference the *same* secret, and the CN has to match the hostname the browser will ask for — that is what the task means by "maintaining the existing HTTPS access configuration". The validator decodes `tls.crt` and greps for the CN to prove the secret is still the right one. |
| 5 | Ingress `web` — host `gateway.web.k8s.local`, path `/` `Prefix`, backend `web-service:80`, annotation `nginx.ingress.kubernetes.io/rewrite-target: /`, `tls` block with hosts `[gateway.web.k8s.local]` and `secretName: web-tls` | `LabSetUp.bash` | This is the **source** of the migration. It is the spec the candidate has to read and translate into two new objects. It is also why the validator insists the Ingress and the Secret are still there afterwards: a migration adds a second front door, it does not delete the first one. |
| 6 | GatewayClass `nginx-class` with `controllerName: example.net/nginx-gateway-controller` | `LabSetUp.bash` | The question says "a GatewayClass named nginx-class is already installed" — so it is a given, not a deliverable. The `controllerName` is a mock namespace because no real nginx Gateway controller is installed; the object only has to exist and be referenced. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | Gateway `web-gateway` with `spec.gatewayClassName: nginx-class` | `LabValidate.bash` |
| B | A listener on that Gateway with `hostname: gateway.web.k8s.local`, `protocol: HTTPS`, `port: 443` | `LabValidate.bash` |
| C | On that listener, `tls.mode: Terminate` and `tls.certificateRefs` containing a reference to the Secret `web-tls` (`kind: Secret`) | `LabValidate.bash` |
| D | HTTPRoute `web-route` with `spec.hostnames` containing `gateway.web.k8s.local` | `LabValidate.bash` |
| E | `spec.parentRefs` on that HTTPRoute containing a reference to the Gateway `web-gateway` | `LabValidate.bash` |
| F | A rule whose match is `path.type: PathPrefix`, `path.value: /` | `LabValidate.bash` |
| G | That rule's `backendRefs` containing `name: web-service`, `port: 80` | `LabValidate.bash` |
| H | The source Ingress `web` and the Secret `web-tls` still exist, and the Secret's certificate CN is still `gateway.web.k8s.local` | `LabValidate.bash` |

## Gotchas

- **A Gateway and an Ingress are two separate front doors, not a replacement.**
  The task says *migrate the configuration*, and the validator holds you to it: the
  Ingress `web` and the Secret `web-tls` must still be there at the end. Deleting
  the Ingress "because you replaced it" is a fail.

- **The Gateway's TLS is not the Ingress's TLS.** The Ingress carries the secret in
  `spec.tls[].secretName`; the Gateway carries it in `spec.listeners[].tls.certificateRefs[]`,
  and each ref is an object with `kind` and `name`, not a bare string. A Gateway
  with a `tls:` block but no `certificateRefs` is missing the certificate.

- **`tls.mode` has to be `Terminate`**, not `Passthrough`. `Passthrough` means the
  Gateway hands the TLS session straight to the backend pod, which would mean the
  nginx Deployment has to terminate TLS itself. Here the Gateway does it, exactly
  like the Ingress did, hence `Terminate`.

- **The listener has to carry the hostname.** A listener with no `hostname` accepts
  every host, and the validator will not find the listener that is supposed to be
  serving `gateway.web.k8s.local`.

- **`parentRefs` is what wires the route to the gateway.** An HTTPRoute that is
  not attached to a Gateway is an inert YAML file. The ref is
  `{name: web-gateway}` — a bare name, resolved in the HTTPRoute's own namespace
  unless you give it a `namespace`.

- **`backendRefs` entries carry the port as a number** (`port: 80`), not as a
  `name:` reference. Mixing the two forms is the classic Gateway API mistake.

- **`gatewayClassName` is a name, not a controller name.** It must be
  `nginx-class`, the name of the GatewayClass object — not
  `example.net/nginx-gateway-controller`, which is the *controllerName* *inside*
  that GatewayClass.

- **There is no Gateway controller installed.** `nginx-class` points at a
  controller that does not exist, so `kubectl get gateway` will show the Gateway
  as `PROGRAMMED: False` / `ACCEPTED: False`. That is expected and it does not
  fail the question: the task is about writing the API objects correctly, and
  the validator reads the objects, not the status.

## Environment requirements

- A cluster you can reach with `kubectl`, and permission to create cluster-scoped
  `GatewayClass` objects plus namespaced `Gateway` / `HTTPRoute` objects.
- **Outbound network access to GitHub**, because `LabSetUp.bash` downloads the
  Gateway API CRDs from
  `https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml`.
  If the machine is offline, install the CRDs by hand first.
- `openssl` on the machine, to mint the self-signed certificate.
- **No Gateway controller is required** — and none is installed. The pre-state
  only has to be able to *hold* the objects.
- The reset **leaves the Gateway API CRDs installed on purpose**. They are
  cluster-scoped, they are shared with any other Gateway API question on the
  same cluster, and `LabSetUp.bash` re-applies the same manifest idempotently —
  so deleting them would gain nothing and would break unrelated questions.
