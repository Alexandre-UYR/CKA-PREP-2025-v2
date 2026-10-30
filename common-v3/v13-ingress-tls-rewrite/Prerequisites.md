# v13 — Two hosts, two certificates: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `ing` | `LabSetUp.bash` | Holds the api, the Service, the two TLS secrets, and the Ingress. Recreated on every run, so the pre-state is always the same. |
| 2 | Deployment `api`, 1 replica, `nginx:1.25`, labels `app=api` | `LabSetUp.bash` | The workload behind the Ingress. It exists so the Ingress has something to route to, and so the Service has a live endpoint. |
| 3 | Service `api`, port 80, selector `app=api` | `LabSetUp.bash` | The backend both hosts route to. The task names it, and the validator checks the Ingress points at it. |
| 4 | TLS secret `api-tls` — self-signed, `CN=api.example.com` | `LabSetUp.bash` (openssl, then `kubectl create secret tls`) | One of the two certificates the candidate must wire in. It already exists, so the candidate's job is the Ingress, not the certificate. |
| 5 | TLS secret `alt-tls` — self-signed, `CN=alt.example.com` | `LabSetUp.bash` (openssl, then `kubectl create secret tls`) | The second certificate, for the second host. Two hosts with two certificates is the shape of the question. |
| 6 | The private key and certificate files removed again after the setup | `LabSetUp.bash` writes them to a temporary directory and removes it | Key material should not be left lying on the machine. The secrets in the cluster are the durable copy. |
| 7 | No Ingress in the namespace | by omission | The Ingress is the deliverable. The candidate creates it from scratch. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | An Ingress `web` in namespace `ing` | `LabValidate.bash` |
| B | `.spec.ingressClassName` is `nginx` | `LabValidate.bash` |
| C | `.spec.tls` has exactly two entries | `LabValidate.bash` |
| D | One TLS entry whose hosts contain `api.example.com` and whose `secretName` is `api-tls` | `LabValidate.bash` |
| E | One TLS entry whose hosts contain `alt.example.com` and whose `secretName` is `alt-tls` | `LabValidate.bash` |
| F | A rule for host `api.example.com` with path `/api`, `pathType: Prefix` | `LabValidate.bash` |
| G | A rule for host `alt.example.com` with path `/`, `pathType: Prefix` | `LabValidate.bash` |
| H | Both rules route to Service `api` on port 80 | `LabValidate.bash` |
| I | The annotation `nginx.ingress.kubernetes.io/rewrite-target` is present, with the value `/` | `LabValidate.bash` |

## Gotchas

- **One TLS entry per host.** The `tls` field is a list, and each entry names
  the Secret that holds the certificate for the host or hosts listed in that
  entry. A single entry with both hosts and one `secretName` points both
  hosts at the *same* certificate — so `alt.example.com` serves the
  `api.example.com` certificate and every client gets a name mismatch. This
  is the mistake the question is built around.

- **`pathType` is required.** In `networking.k8s.io/v1` the API server
  rejects an Ingress whose path has no `pathType`. `Prefix` and `Exact` are the
  two values that matter here; `ImplementationSpecific` is the legacy
  behaviour of the old `extensions/v1beta1` API.

- **The rule and the TLS entry are separate lists, and both have to name the
  host.** A rule without a `host` matches every host, and a TLS entry without
  a host matches every host too. The pairing the candidate has to get right is
  the one between a host in `tls` and a host in `rules`.

- **The rewrite annotation is a controller convention, not API validation.**
  `nginx.ingress.kubernetes.io/rewrite-target: /` tells the ingress controller
  to replace the matched path with `/` before the request is forwarded. The
  API server does not check it, does not default it, and does not care which
  controller you use — so the check reads the annotation on the object.

- **`ingressClassName` is not the same as the old `kubernetes.io/ingress.class`
  annotation.** On `networking.k8s.io/v1` the field is the modern way, and
  the task asks for it by name.

- **The rewrite only makes sense together with the path.** `/api` on
  `api.example.com` rewritten to `/` is what lets the nginx backend answer,
  since the container serves `/`. The annotation applies to the whole Ingress,
  so the `/` path on `alt.example.com` is rewritten to `/` as well — which is
  a no-op.

## Environment requirements

- A cluster with at least one node, and registry access for `nginx:1.25`.
- **No ingress controller is needed.** The Ingress is an API object: it can be
  created, read and graded on any cluster, including one with no controller
  and no controller configuration. The checker reads the Ingress itself, so
  the checks do not depend on TLS actually being served, on DNS for
  `api.example.com`, or on the self-signed certificates being trusted. The
  certificates are self-signed on purpose: they only have to exist, with the
  right common name, for the candidate to pair each host with the right
  Secret.
- `openssl` on the machine running the setup, to generate the two
  self-signed certificates. The setup stops with a clear message if it is
  missing.
