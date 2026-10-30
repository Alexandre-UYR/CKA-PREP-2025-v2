# Q17 — TLS Config: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `nginx-static` | `LabSetUp.bash` | The namespace the question names, and where the ConfigMap, Secret, Deployment and Service all live. |
| 2 | TLS Secret `nginx-tls`, self-signed, **CN = `ckaquestion.k8s.local`** | `LabSetUp.bash` (`openssl req -x509` piped into `kubectl create secret tls`) | The server certificate. The CN has to match the hostname the client uses, otherwise the TLS handshake fails on the certificate name even when the protocol version is right — and you would be debugging the wrong thing. |
| 3 | ConfigMap `nginx-config` whose `nginx.conf` contains `ssl_protocols TLSv1.2 TLSv1.3;` and a server block `listen 443 ssl` pointing at `/etc/nginx/tls/tls.crt` / `tls.key` | `LabSetUp.bash` | The object you have to change. It starts with **both** versions enabled, which is what makes the question a question: you cannot tell whether TLS 1.2 still works until you have taken TLS 1.2 out. |
| 4 | Deployment `nginx-static` (1 replica, labels `app=nginx-static`) mounting the ConfigMap at `/etc/nginx/nginx.conf` with `subPath: nginx.conf` and the Secret at `/etc/nginx/tls` | `LabSetUp.bash` | The workload that serves the TLS endpoint. The `subPath` mount is what makes the ConfigMap's `nginx.conf` replace the image's own file. |
| 5 | Service `nginx-service` in `nginx-static`, ClusterIP, port 443 -> targetPort 443, selector `app: nginx-static` | `LabSetUp.bash` | The question says "There is a service called nginx-service in the nginx-static namespace that is currently exposing the deployment" — so it is a given, and it is the address you have to put in `/etc/hosts`. It selects the deployment's pods, so traffic to the ClusterIP reaches the nginx pod on port 443. |
| 6 | The pod's `creationTimestamp` and the setup's finish time, recorded in `/tmp/cka-lab/q17.pod.before` and `/tmp/cka-lab/q17.setup.time` | `LabSetUp.bash` | The evidence that the pods were **recreated** after the ConfigMap was edited. See the gotcha below — this is the check that catches the most common wrong answer. |
| 7 | The `nginx:latest` image and `openssl` on the node, and outbound registry access | the cluster / `LabSetUp.bash` | The deployment pulls nginx; the setup mints the certificate with openssl. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | ConfigMap `nginx-config`'s `nginx.conf` contains `TLSv1.3` | `LabValidate.bash` |
| B | …and no longer contains `TLSv1.2` anywhere | `LabValidate.bash` |
| C | The `nginx-static` pod has been **recreated** (its `creationTimestamp` is newer than the pod the setup created) — i.e. the Deployment was restarted | `LabValidate.bash` |
| D | The Deployment still has 1 ready replica | `LabValidate.bash` |
| E | `/etc/hosts` contains an entry for `ckaquestion.k8s.local` | `LabValidate.bash` |
| F | The IP in that entry equals the ClusterIP of the `nginx-service` Service | `LabValidate.bash` |
| G | `curl -vk --tls-max 1.2 https://ckaquestion.k8s.local` **fails** | `LabValidate.bash` (skipped, with a reason, if this machine cannot reach the ClusterIP) |
| H | `curl -vk --tlsv1.3 https://ckaquestion.k8s.local` **succeeds** | `LabValidate.bash` (same skip rule) |

## Gotchas

- **Editing a ConfigMap does not restart the pods that mount it.** This is the
  heart of the question. A ConfigMap volume is a *projection*: the file in the
  container is refreshed by kubelet within about a minute, but nginx only reads
  `nginx.conf` at start-up. So if you only edit the ConfigMap, the running nginx
  is still serving TLS 1.2 and your `curl --tls-max 1.2` still succeeds. You
  also have to restart the workload:
  `kubectl -n nginx-static rollout restart deployment nginx-static`.
  That is why the validator compares the **pod's creation timestamp** against
  the pod the setup created: a candidate who edited the ConfigMap and stopped
  there has not finished the task, and the object-only checks would happily
  pass them.

- **`ssl_protocols` takes a list, and you delete rather than comment out.**
  `ssl_protocols TLSv1.2 TLSv1.3;` becomes `ssl_protocols TLSv1.3;`. If you leave
  `TLSv1.2` anywhere in the file — even in a comment — the validator counts it
  as still enabled.

- **The certificate CN must match the hostname you curl.** The secret is minted
  with `CN=ckaquestion.k8s.local`, so that is the name you put in `/etc/hosts`.
  Using the ClusterIP directly in the URL would fail the certificate name check
  (you would need `-k` / `--insecure`, and the hostname check would be
  meaningless).

- **`/etc/hosts` needs the ClusterIP, not the pod IP and not the node IP.**
  `kubectl -n nginx-static get svc nginx-service -o jsonpath='{.spec.clusterIP}'`
  gives the address; the pods behind it are an implementation detail. The
  ClusterIP is stable for the life of the Service, so this is the right thing to
  hard-code.

- **`/etc/hosts` is a file on the machine you type on**, not on the node. If you
  ran the setup on a remote cluster and you are validating from your laptop, the
  entry has to be in *your* laptop's `/etc/hosts` — and the ClusterIP is only
  routable from inside the cluster's network. That is why the validator checks
  whether it can open a TCP connection to the ClusterIP before it tries the TLS
  handshake, and prints a `SKIP` line instead of a fake pass when it cannot.

- **Editing a ConfigMap with `kubectl edit` leaves the `kubectl.kubernetes.io/last-applied-configuration`
  annotation behind.** The solution notes suggest removing TLSv1.2 from that
  annotation too, for safety. It is not strictly necessary — the annotation is
  metadata, not configuration — but it does stop `kubectl apply` from putting
  TLSv1.2 back later.

- **A `rollout restart` briefly takes the pod out of service.** If you validate
  straight after restarting, the pod may not be Ready yet. The validator waits
  for the ready replica before checking, so give it a moment.

## Environment requirements

- Write access to `/etc/hosts` on the machine running the validator (normally
  `sudo`). The validator reads it as the current user and falls back to
  `sudo -n`; with neither available it reports a clear failure rather than
  silently skipping the check.
- **The machine running the validator must be able to reach the Service's
  ClusterIP on port 443** for the TLS 1.2 / TLS 1.3 checks to be meaningful.
  On a laptop talking to a cluster in another network, a ClusterIP is usually
  not routable, and the validator prints a `SKIP` with the reason. The object
  checks still grade the answer.
- `curl` built against a TLS 1.3-capable TLS library (OpenSSL 1.1.1 or later)
  with `--tlsv1.3` and `--tls-max` support. The validator probes for both and
  skips with a reason if they are missing.
- `openssl` on the machine running the setup, to mint the self-signed
  certificate.
- Outbound access to a container registry, so the `nginx:latest` image can be
  pulled.
