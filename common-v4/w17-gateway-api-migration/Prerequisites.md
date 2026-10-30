# w17 — Move the routing to the new API without changing the outside: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `gw` | `LabSetUp.bash` | The Ingress, the Gateway and the HTTPRoute all live here. |
| 2 | Deployment `web` — nginx:1.25, 1 replica, labels `app=web` | `LabSetUp.bash` | The backend behind the routing. It has to stay exactly as it is, so the grader compares its UID with the one recorded at setup time. |
| 3 | Service `web` — port 80 named `http`, selector `app=web` | `LabSetUp.bash` | The backend the Ingress routes to and the HTTPRoute has to route to. Also compared by UID, so it must not be recreated. |
| 4 | Secret `web-tls` — a self-signed certificate for `gateway.web.k8s.local` | `LabSetUp.bash` (openssl) | The certificate the Ingress serves and the one the Gateway listener has to terminate with. The whole point is that the certificate served does not change, so it is the same Secret, named the same way. |
| 5 | Ingress `web` — host `gateway.web.k8s.local`, TLS block with `secretName: web-tls`, path `/` `Prefix` to Service `web` port 80, annotation `nginx.ingress.kubernetes.io/rewrite-target: /` | `LabSetUp.bash` | The thing being replaced. It is the specification of the outside: the candidate has to reproduce every part of it with the Gateway API and then take it away. |
| 6 | GatewayClass `nginx-class`, controller `example.net/nginx-gateway-controller` | `LabSetUp.bash` | The class the Gateway has to name in `spec.gatewayClassName`. It is pre-state, so the candidate does not create it. |
| 7 | The `gatewayclasses` CRD installed, the `gateways` and `httproutes` CRDs NOT installed | `LabSetUp.bash` | This is the pre-state the task describes. The GatewayClass can be read, but a Gateway or an HTTPRoute cannot be created until the CRDs are put back. |
| 8 | The Gateway API release manifest at `/tmp/cka-lab/gateway/standard-install.yaml` | `LabSetUp.bash` | The setup downloads it while it still has network access. It is a copy of the official manifest, and it is what the candidate's `kubectl apply -f` is expected to install. |
| 9 | Copies of the pre-state manifests under `/tmp/cka-lab/gateway/` | `LabSetUp.bash` | `deployment.yaml`, `service.yaml`, `secret.yaml`, `ingress.yaml`, `gatewayclass.yaml`. The reset uses them to put the pre-state back, including the Ingress. |
| 10 | The UID of the Deployment, the Service and the Ingress recorded in `pre-state-uid.txt` | `LabSetUp.bash` | So the grader can tell that the Service and the Deployment were left alone rather than deleted and recreated with the same content. |
| 11 | Registry access for `nginx:1.25` | the environment | The backend has to be running for the pre-state to be meaningful. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | The Gateway API CRDs installed | `LabValidate.bash` — `gatewayclasses`, `gateways` and `httproutes` |
| B | Gateway `web-gateway` in namespace `gw` | `LabValidate.bash` |
| C | The Gateway uses `gatewayClassName: nginx-class` | `LabValidate.bash` |
| D | A listener with protocol HTTPS, port 443, hostname `gateway.web.k8s.local`, `tls.mode: Terminate` and a `certificateRef` naming `web-tls` | `LabValidate.bash` |
| E | HTTPRoute `web-route` in namespace `gw` | `LabValidate.bash` |
| F | The HTTPRoute serves the hostname `gateway.web.k8s.local` and names the Gateway `web-gateway` as its parent | `LabValidate.bash` |
| G | A rule matching the path prefix `/`, with a backendRef to Service `web` on port 80 | `LabValidate.bash` |
| H | The Ingress `web` no longer exists | `LabValidate.bash` |
| I | The Service `web` and the Deployment `web` untouched | `LabValidate.bash` — same UID as the setup recorded, same image, replicas and port |

## Gotchas

- **In the Ingress, TLS lives in a `spec.tls` block that lists the hosts and
  the secret; in the Gateway API, TLS lives on the LISTENER, and each listener
  has one hostname.** So the Ingress's `spec.tls[0].hosts[0]` becomes the
  listener's `hostname`, and the Ingress's `spec.tls[0].secretName` becomes
  the listener's `tls.certificateRefs[0].name`.

- **The Certificate that the Ingress referred to becomes a `certificateRef` —
  the same Secret, named the same way, so the certificate served is
  unchanged.** The Secret `web-tls` is not recreated and its contents are not
  touched. A Gateway that points at a different Secret, or at a Secret that
  does not exist, serves a different certificate or nothing at all.

- **Leaving the Ingress in place would mean two objects claiming the same
  hostname.** `gateway.web.k8s.local` would be served by the Ingress and by
  the Gateway at the same time, and it would not be clear which one the
  traffic reaches. The Ingress has to be deleted, not edited or left to
  "fall out of use".

- **The GatewayClass already exists; the CRDs the Gateway and the HTTPRoute
  need do not.** The `gateways` and `httproutes` CRDs are missing in the
  pre-state, so `kubectl apply` of a Gateway fails with "no matches for kind
  Gateway" until they are installed. The `gatewayclasses` CRD is still there,
  which is why the GatewayClass can be read.

- **A listener has exactly one hostname.** A Gateway that serves two
  hostnames needs two listeners, not one listener with two names.

- **The HTTPRoute's rules hold the path match and the backend; the Gateway
  holds the TLS.** The Ingress's `spec.rules[0].http.paths[0]` splits across
  the two objects: the path goes into the HTTPRoute's `rules[].matches[]`, the
  backend goes into `rules[].backendRefs[]`, and the host goes into the
  HTTPRoute's `spec.hostnames[]` — not into the Gateway, which carries the
  hostname on the listener.

- **`parentRefs` names the Gateway, and it is namespaced.** `parentRefs[0].name`
  is the Gateway's name; the namespace is the route's own namespace unless
  `namespace:` is given.

- **The `rewrite-target` annotation has no equivalent in the standard
  Gateway API.** It was an nginx-ingress instruction; the closest thing is a
  `URLRewrite` filter, which is not in the standard channel. Nothing is lost
  here, because the backend serves `/` anyway.

- **The controller in this cluster does not exist.**
  `example.net/nginx-gateway-controller` is a name, not a running controller,
  so the Gateway will never report itself as Programmed. The question is
  about moving the configuration across, and there is no live check to pass.

## Environment requirements

- A cluster with at least one node, and registry access for `nginx:1.25`.
- **Network access to `https://github.com/kubernetes-sigs/gateway-api`** when
  the Gateway API CRDs are installed. The setup downloads the standard channel
  manifest from there; if it cannot, it says so and the candidate has to
  install the CRDs themselves.
- `openssl` on the machine running the setup, for the self-signed certificate.
  Without it the setup falls back to a placeholder certificate and says so.
- A writable `/tmp` — the manifests, the downloaded CRD bundle and the UID
  record live under `/tmp/cka-lab/gateway`.
