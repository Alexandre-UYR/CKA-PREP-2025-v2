# Q6 — CRDs: prerequisite inventory

The exam hands you a cluster and a task. This file lists everything that was
already in the cluster when you opened the task, and why each piece is there.

## Prerequisite inventory

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `cert-manager` | `LabSetUp.bash` | cert-manager's own components live in this namespace, and it is where the minimal cert-manager Deployment sits. It gives the question a realistic "cert-manager is installed" look. |
| 2 | The six cert-manager v1.14.0 CRDs | `LabSetUp.bash` (applied from the upstream `cert-manager.crds.yaml` for v1.14.0) | The task says "a list of all cert-manager CRDs". There has to be a set of cert-manager CRDs in the cluster to list, and they must be the real upstream ones so the names and the schema are the real thing. |
| 3 | `certificates.cert-manager.io` established (the `Certificate` custom resource) | `LabSetUp.bash` (CRD apply, then wait for `Established`) | The second half of the task asks for `kubectl explain` on the `subject` field of the `Certificate` custom resource. `kubectl explain` resolves custom resources through the CRD's OpenAPI schema, so the CRD has to be installed *and* established. |
| 4 | A minimal `cert-manager` Deployment in that namespace | `LabSetUp.bash` | Makes the namespace look like a real cert-manager install, so `kubectl get crd` output is not the only hint that cert-manager is present. The task never asks you to touch it. |

The CRDs that are installed:

```
certificaterequests.cert-manager.io
certificates.cert-manager.io
challenges.acme.cert-manager.io
clusterissuers.cert-manager.io
issuers.cert-manager.io
orders.acme.cert-manager.io
```

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| 1 | `/root/resources.yaml` exists and is not empty | file exists, content length > 0 |
| 2 | `/root/resources.yaml` lists the cert-manager CRDs (all six names appear) | each CRD name is searched for in the file |
| 3 | `/root/subject.yaml` exists and is not empty | file exists, content length > 0 |
| 4 | `/root/subject.yaml` documents the `subject` field | the string `subject` appears in the file |

## Gotchas

- **The files go in `/root`, not your home directory.** That directory is
  writable only by root, so the commands need `sudo` (or you run them as
  root). `sudo tee /root/resources.yaml` is the usual pattern; a plain
  `> /root/resources.yaml` from a normal shell fails with "Permission denied".
- **`kubectl get crd` output is the easy half.** The plain list output contains
  the CRD names, so `kubectl get crd | grep cert-manager | tee /root/resources.yaml`
  is enough. The task says "any output format that kubectl supports", so
  `kubectl get crd -o yaml` is equally valid — it just makes a much bigger file.
- **`kubectl explain` needs the field path, not the field name alone.**
  `kubectl explain certificate.spec.subject` is the form that gives you the
  `subject` documentation; `kubectl explain certificate` gives you the whole
  resource and would not mention `subject` in a way the grader can use.
- **The first line of the explain output matters:** it is
  `KIND: Certificate   VERSION: v1   FIELD: subject <Object>`. That is the
  line the grader looks for.
- **The cert-manager CRDs are deliberately left in place by `LabReset.bash`.**
  They are cluster-scoped, and deleting them destroys every `Certificate`
  object in the whole cluster, including ones that have nothing to do with
  this lab. `LabSetUp.bash` re-applies them idempotently, so the pre-state is
  intact either way.
- **`kubectl explain` on a CRD needs the CRD to be `Established`.** If you run
  it right after the setup it may say "no matches for kind Certificate". Give
  it a second; the setup waits for this.

## Environment requirements

- **Write access to `/root`** (root shell, or `sudo` with a passwordless or
  cached credential). The grader reads the two files with a plain `cat` first
  and falls back to `sudo -n cat`.
- **No node-level access is needed.** Everything is API-server-side plus two
  files on the machine you type the commands on.
- **The cluster must be able to reach the upstream release URL** for the
  cert-manager CRDs, or the CRDs must be pre-seeded in the image. Otherwise
  `LabSetUp.bash` fails at the CRD apply and the question cannot start.
- **The cert-manager Deployment is not required to be Running.** The task is
  about CRDs and `kubectl explain`, both of which are served by the API server.
  A pod that is `ImagePullBackOff` does not affect the answer.
