# w16 — Get a Host header to the right place: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `web` | `LabSetUp.bash` | The Ingress, the third page and the probe pod all live here. |
| 2 | Deployment `thirdpage` — nginx:1.25, 1 replica, labels `app=thirdpage` | `LabSetUp.bash` | The backend the Ingress has to reach. It has to be running and ready, or the live check gets a 503 instead of the marker. |
| 3 | Service `thirdpage` — port 80 named `http`, selector `app=thirdpage` | `LabSetUp.bash` | The name the Ingress backend points at. The port is named `http` as well as numbered, so a backend may refer to it either way. |
| 4 | ConfigMap `nginx-conf` | `LabSetUp.bash` | The nginx configuration the third page runs. It answers with the marker string `thirdpage-marker` and the hostname it was asked for, so the response says both that the right page answered and that the Host header decided where the request went. |
| 5 | The Deployment mounts `nginx-conf` at `/etc/nginx/conf.d/default.conf` | `LabSetUp.bash` | The configuration has to be in the container for the marker to appear in the response. |
| 6 | Pod `probe` in namespace `web`, image `curlimages/curl` | `LabSetUp.bash` | A pod with curl in it, so a request can be sent from inside the cluster. The validator uses it, and so can the candidate. |
| 7 | No ingress controller | `LabSetUp.bash` | The release in namespace `traefik` is uninstalled and the namespace is deleted, so the candidate starts from nothing. |
| 8 | Namespace `traefik` absent | `LabSetUp.bash` | The candidate creates it, as the task asks. |
| 9 | Ingress `web` removed | `LabSetUp.bash` | The Ingress is the candidate's answer, not part of the pre-state. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | A Helm release in namespace `traefik` with status `deployed`, from the traefik chart | `LabValidate.bash` — `helm list` and `helm status` |
| B | Namespace `traefik` | `LabValidate.bash` |
| C | Ingress `web` in namespace `web` | `LabValidate.bash` |
| D | The Ingress has a rule for the host `www.example.com` | `LabValidate.bash` |
| E | That rule sends traffic to the Service `thirdpage` on port 80 | `LabValidate.bash` — the backend service name and port, read out of the rule that carries that host |
| F | The Ingress uses the ingress class `traefik` | `LabValidate.bash` — a wrong class is a failure; no class at all is reported as a note, because it can still work if traefik is the default class |
| G | A live request from inside the cluster | `LabValidate.bash` — HTTP 200, a body containing `thirdpage-marker`, and a body containing the hostname that was asked for |

## Gotchas

- **An Ingress routes by HOST as well as by path, so the Host header is what
  decides which rule matches** — which is why the request has to carry it. A
  request to the Traefik Service with no Host header, or with the wrong one,
  gets a 404, even though the Service is being reached perfectly well.

- **The ingress controller has to be installed and reachable for any of it to
  work; creating the Ingress object alone changes nothing.** The Ingress is a
  piece of configuration that a controller reads. With no controller there is
  nothing to route the request to.

- **The Ingress has to name the ingress class `traefik`.** The chart installs
  an IngressClass by that name and Traefik only watches the Ingresses that name
  it. An Ingress with no `ingressClassName` is ignored unless the controller
  has been made the default one for the cluster.

- **The response body proves two things at once.** `thirdpage-marker` says the
  request reached the third page; `host=www.example.com` says it reached it
  through the rule for that hostname, rather than by some other route.

- **Inside the cluster, the Service is reached by its cluster DNS name**, not
  by the LoadBalancer address. `http://traefik.traefik.svc.cluster.local/`
  works on any cluster; the LoadBalancer address only resolves if the cluster
  has a load balancer provider, and the chart's Service stays `<pending>`
  without one.

- **The chart is installed from a Helm repository, not from a path**, so the
  repository has to be added first with `helm repo add`.

## Environment requirements

- A cluster with at least one node.
- `helm` on the machine running the commands, and network access to
  `https://helm.traefik.io` to fetch the chart, plus registry access for the
  chart's images.
- Registry access for `nginx:1.25` and for `curlimages/curl`.
- A working CNI and DNS. The live check runs from a pod inside the cluster
  and talks to the Traefik Service over the cluster network, so it needs
  both.
- **If the chart cannot be installed, or the Traefik Service cannot be reached
  from inside the cluster, the live check is skipped** with the reason
  printed, and the object checks are still graded. The two halves of the
  question stand on their own: the objects show what was configured, the live
  check shows that it works.
