# Q12 — Ingress: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `echo-sound` | `LabSetUp.bash` | The question names the namespace twice ("a Service called echo-service" and "an Ingress named echo in the echo-sound namespace"), so it is a given, not something you create. |
| 2 | Deployment `echo` — image `gcr.io/google_containers/echoserver:1.10`, container port `8080`, pod labels `app=echo` | `LabSetUp.bash` | The workload being exposed. The echoserver answers any path with a small HTML body, which is why the question's verification path is `/echo` — the path is arbitrary, the point is that *something* answers with HTTP 200. |
| 3 | The `echo` pods have labels `app=echo` | `LabSetUp.bash` (`selector.matchLabels` and `template.metadata.labels` are both set) | The Service you write has to *select* those pods. If the deployment's pod labels did not match anything, a Service with the wrong selector would still exist and still look correct in `kubectl get svc` — the only way to tell is to look at the Endpoints. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | Service `echo-service` in namespace `echo-sound` | `LabValidate.bash` |
| B | `spec.type: NodePort` | `LabValidate.bash` |
| C | `spec.ports[0].port: 8080` | `LabValidate.bash` |
| D | `spec.ports[0].targetPort: 8080` | `LabValidate.bash` |
| E | A `nodePort` allocated by the cluster (the exact number is the cluster's choice — do not hard-code it) | `LabValidate.bash` |
| F | A selector that matches the `echo` deployment's pods, so the Service has at least one endpoint address | `LabValidate.bash` |
| G | Ingress `echo` in namespace `echo-sound` | `LabValidate.bash` |
| H | `spec.rules[0].host: example.org` | `LabValidate.bash` |
| I | `spec.rules[0].http.paths[0].path: /echo` with `pathType: Prefix` | `LabValidate.bash` |
| J | Backend `service.name: echo-service`, `service.port.number: 8080` | `LabValidate.bash` |
| K | Live check: `curl NODEIP:NODEPORT/echo` returns 200 | `LabValidate.bash` (skipped, with a reason, if this machine cannot reach the node) |

## Gotchas

- **`port` and `targetPort` are different numbers.** `port: 8080` is what clients
  connect to (the Service port, and for a NodePort the port that gets published on
  every node); `targetPort: 8080` is the container port the traffic is forwarded
  to. Here they happen to be the same, which is a coincidence of the echoserver's
  port — not a rule.

- **The `nodePort` is assigned by the cluster.** You ask for a `NodePort` Service
  and the API server picks a port from the node-port range (30000-32767 by
  default). You may request a specific one with `nodePort: 30080`, but the
  question does not ask for that, and hard-coding a number is how you end up
  fighting the cluster when it is already in use.

- **`kubectl expose deployment echo --name echo-service --type NodePort` writes
  the selector for you**, taken from the deployment's pod labels. If you write the
  Service by hand and forget `selector: {app: echo}`, the Service looks perfect
  and routes traffic into a void. The Endpoints (or EndpointSlices) are where you
  see the truth.

- **`kubectl expose` defaults the target port to the container port**, so
  `--port=8080` alone gives you `port: 8080` / `targetPort: 8080`. Passing
  `--target-port` explicitly is clearer.

- **An Ingress object on its own does nothing.** Nothing serves it until an
  ingress controller is running in the cluster and picks it up. This lab does
  **not** install one — the graded part of the question is the API objects, and
  the live check deliberately goes through the **NodePort** (which kube-proxy
  publishes on every node, with no controller involved), not through the Ingress.

- **The `/etc/hosts` entry is optional manual verification, not a deliverable.**
  To test the Ingress by name you need `example.org` to resolve to the node's
  IP, i.e. a line like `<nodeIP> example.org` in `/etc/hosts`. That entry is part
  of the exam's "verify it yourself" step; the validator does not grade it, and
  the reset removes it if you added it.

- **`spec.rules[0].http.paths[0]` is the shape the question describes.** The
  validator reads that exact path, so keep the rule and the path as the first
  (and only) entry rather than adding extra rules ahead of it.

## Environment requirements

- A cluster reachable with `kubectl`, and permission to create namespaced
  Services and Ingresses.
- **No ingress controller is required.** The Ingress is graded by reading the
  object. If you want to test `http://example.org/echo` for real, you need an
  ingress controller installed and an `/etc/hosts` entry pointing `example.org`
  at the node IP — and the controller must be configured to serve the
  `example.org` host.
- **The NodePort live check needs the machine running the validator to be able
  to reach the node's IP on the allocated node port.** That is not true of every
  setup — with a remote cluster or a node behind NAT it will fail. When that
  happens the validator prints a `SKIP` line with the reason instead of
  pretending it passed, and the static checks still grade the answer.
- Write access to `/etc/hosts` (usually via `sudo`) if you want to do the
  optional manual verification.
- The `echo` image `gcr.io/google_containers/echoserver:1.10` comes from the old
  `gcr.io/google_containers` repository, which now redirects to
  `registry.k8s.io`. The node needs outbound access to pull it.
