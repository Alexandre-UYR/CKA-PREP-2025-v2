# x7 — A certificate, issued: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `pki` | `LabSetUp.bash` | The Issuer, the Certificate and the Secret all live here, and the task names the namespace. The setup deletes and re-creates the namespace on each run. |
| 2 | The cert-manager CRDs — `certificates.cert-manager.io`, `certificaterequests.cert-manager.io`, `issuers.cert-manager.io`, `clusterissuers.cert-manager.io` and the two ACME ones | `LabSetUp.bash` | Without the CustomResourceDefinitions there is no `Certificate` kind to create. The setup applies the CRDs from the cert-manager v1.14.0 release and waits for them to be **Established**. |
| 3 | A cert-manager controller running in the `cert-manager` namespace | `LabSetUp.bash` | The controller is what reads a Certificate and does the work. The CRDs alone are just a schema; nothing would ever issue anything. |
| 4 | An Issuer manifest at `/tmp/cka-lab/issuer.yaml` — a self-signed Issuer named `selfsigned` in namespace `pki` | `LabSetUp.bash` | The file the candidate applies. The task does not ask for the Issuer to be written from scratch, so the setup hands it over. |
| 5 | The setup waits for the CRDs to be Established and for the controller to be available | `LabSetUp.bash` | A Certificate created before the CRD is Established is rejected by the API server, and a Certificate created before the controller runs simply sits there. The starting state has to be one in which the answer can actually work. |
| 6 | Network access to the cert-manager release and to the `quay.io` registry | the environment | The setup downloads the CRDs and pulls the controller image. Without network the setup says so loudly and the question cannot be run. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | The Issuer `selfsigned` exists in namespace `pki` and is **Ready** | `LabValidate.bash` — the Issuer's `status.conditions[type=Ready]` |
| B | The Certificate `test-cert` exists in namespace `pki` | `LabValidate.bash` |
| C | Its `spec.issuerRef.name` is `selfsigned` | `LabValidate.bash` |
| D | Its `spec.commonName` is `example.com` | `LabValidate.bash` |
| E | Its `spec.dnsNames` contains `example.com` | `LabValidate.bash` |
| F | Its `spec.secretName` is `test` | `LabValidate.bash` |
| G | The Secret `test` exists in namespace `pki` with a non-empty `tls.crt` | `LabValidate.bash` |
| H | The certificate in that Secret has `example.com` as its subject | `LabValidate.bash` — the base64 is decoded and searched for `example.com` |

## Gotchas

- **A Certificate is a REQUEST, not a certificate.** Creating the
  `Certificate` object proves nothing on its own: it is a piece of paper
  saying "I would like a certificate with these properties". cert-manager's
  controller reads it, asks the Issuer to sign a CertificateRequest, and
  writes the result into a Secret. **The Secret is the evidence.** A
  candidate who creates the Certificate and stops there has asked for a
  certificate and received nothing.

- **The Secret is written by the controller, so it takes a moment.** The
  controller watches for new Certificate objects and reconciles them, which
  usually takes a second or two. `kubectl get secret -n pki` right after the
  `apply` can easily come back empty. `kubectl get certificate -n pki -o
  yaml` shows the `status` conditions while the work is happening, and the
  reason a Certificate is not being issued is written there and in the
  controller's logs.

- **An Issuer describes WHERE a certificate comes from.** It is not the
  certificate itself, and it is not a certificate request. An Issuer is the
  authority that signs: a self-signed Issuer is its own authority, a CA
  Issuer points at a key pair in a Secret, an ACME Issuer talks to an ACME
  server. `spec.selfSigned: {}` is all a self-signed Issuer needs.

- **The Issuer has to be Ready before it can sign.** Its status carries a
  `Ready` condition, and for a self-signed Issuer that condition means the
  controller has found it and can use it. `kubectl get issuer -n pki` shows
  the condition as READY or NOT READY.

- **`secretName` is a promise about a Secret, not a request for a Secret
  with a given name.** The controller creates the Secret and puts the
  private key in `tls.key` and the signed certificate in `tls.crt`. A
  Secret with the right name but nothing in `tls.crt` is not a certificate.

- **A `Certificate` needs `commonName`, `dnsNames` or `uriSANs`, or the API
  server rejects it.** A certificate with no subject at all is not a
  certificate, and the Issuer will not sign it.

- **The CRDs are cluster-scoped and must not be deleted.** `Certificate`,
  `Issuer` and the rest are namespaced objects, but the CRDs that define
  them live in the cluster scope. Deleting a CRD deletes every object of
  that kind in the whole cluster, and cert-manager's own installation
  breaks with it. The reset for this question deliberately leaves the CRDs
  and the controller in place.

- **`kubectl get certificate` and `kubectl get cert` are the same command.**
  The resource is `certificates.cert-manager.io`, and the short name is
  `cert`.

## Environment requirements

- A cluster with network access, so that the setup can download the
  cert-manager CRDs from the release and pull the controller image. If there
  is no network the setup prints a clear warning and the question cannot be
  run; the validator says the same rather than failing the candidate for a
  missing component.
- Permission to create cluster-scoped objects (the CRDs, the controller's
  ClusterRole and ClusterRoleBinding) — in practice, cluster-admin.
- The cert-manager CRDs must not already be in use by another cert-manager
  installation with a different version. The setup uses the CRDs that are
  there if they exist, and installs v1.14.0's otherwise.
