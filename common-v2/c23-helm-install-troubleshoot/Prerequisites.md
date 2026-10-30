# c23 — Install a chart and fix it when it fails: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `webapps` | `LabSetUp.bash` | The task installs the release into it. Helm creates nothing else for the candidate: the namespace has to exist before `helm install` is asked to put the release there. |
| 2 | `helm` on the PATH | the machine | The task is written in Helm's vocabulary — `helm install`, `helm list`, `helm status`, `helm upgrade`. Nothing else in the question works without it. |
| 3 | A local chart at `/tmp/cka-lab/charts/broken-chart` (`Chart.yaml`, `values.yaml`, `templates/deployment.yaml`) | `LabSetUp.bash` | The candidate has to fix this chart. It is local on purpose: the lab must not depend on a public repository, on network access, or on what some remote index happens to contain today. |
| 4 | The chart's Deployment `broken-chart` asks for the image `nginx:0.0.0-does-not-exist` | `LabSetUp.bash` | This is the fault. The release installs cleanly, the Deployment is created, and the pod then sits in `ImagePullBackOff` because that tag was never published. |
| 5 | A pristine copy of the chart at `/tmp/cka-lab/charts/.pristine-broken-chart` | `LabSetUp.bash` | The candidate edits the working copy. Without a pristine copy the reset could not put the fault back, and the second attempt would start from the first attempt's fix. |
| 6 | A cluster with a node that can pull `nginx` once the tag is fixed | the cluster itself | The fixed image has to be pullable, otherwise the release stays broken for a different reason and the answer cannot be right. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | A Helm release named `broken` in namespace `webapps` | `LabValidate.bash` |
| B | The release's status is `deployed` | `LabValidate.bash` |
| C | `helm status broken -n webapps` succeeds and reports the release as deployed | `LabValidate.bash` |
| D | The chart's Deployment exists in `webapps` (named `broken-chart`, or found by the release's labels) | `LabValidate.bash` |
| E | The Deployment asks for 1 replica and has 1 ready replica | `LabValidate.bash` |
| F | The container image is no longer the broken one | `LabValidate.bash` |
| G | Every pod of the Deployment is `Running` | `LabValidate.bash` |
| H | `/tmp/cka-lab/charts/broken-chart/templates/deployment.yaml` no longer contains the broken image tag | `LabValidate.bash` |

## Gotchas

- **`helm install` reports success even when the workload it creates is
  broken.** Helm only knows that the objects were created. It does not pull
  the image, it does not wait for the pod to be ready, and it does not care
  whether the Deployment will ever schedule. A green `helm install` and a
  broken pod are entirely compatible, and the whole point of this question is
  that the real diagnosis has to happen *after* the install.

- **The diagnosis is `helm status`, `kubectl get pods -n webapps` and the
  pod's own events.** `helm status` tells you the release exists and what
  revision it is on; `kubectl get pods` tells you the pod is `Pending` rather
  than `Running`; `kubectl describe pod` (or `kubectl get events`) tells you
  *why*: `Failed to pull image "nginx:0.0.0-does-not-exist"`. The release
  looks fine from Helm's side, and the fault only shows up one layer down.

- **A chart change only reaches the cluster on the next `helm upgrade`.**
  Editing the files on disk changes what the *next* render would produce, and
  nothing else. The release that is already installed holds its own rendered
  manifest. After fixing `templates/deployment.yaml` the candidate still has
  to run `helm upgrade broken /tmp/cka-lab/charts/broken-chart -n webapps` —
  otherwise the Deployment keeps the old image and the pod keeps failing, and
  the chart on disk looks correct the whole time.

- **`helm upgrade` with a local path is the same as with a repository.** The
  path is read and re-rendered on every command; there is no `helm repo
  update` to forget.

- **The image tag in this chart is hard-coded in the template, not read from
  `values.yaml`.** That is deliberate: `helm upgrade --set image.tag=...`
  cannot fix it, because the template never asks `values.yaml` for the tag.
  The file on disk has to change.

- **The Deployment is named `broken-chart`, not `broken`.** The release name
  and the resource name are different things. The chart also labels the
  Deployment with `app.kubernetes.io/instance: broken`, so
  `kubectl -n webapps get deploy -l app.kubernetes.io/instance=broken` finds
  it however it is named.

- **`helm list` hides some states by default.** `helm list` without
  `--all` only shows the releases in the states it considers interesting; a
  release that is `pending-install` or `uninstalled` may not appear at all.
  `helm list -n webapps --all` shows every release in the namespace, which is
  what you want while diagnosing.

- **`helm uninstall` before you reinstall.** A release name cannot be reused
  while the old release is still installed: `helm install` fails with
  "cannot re-use a name that is still in use". `helm upgrade` is the way
  forward when you want to keep the release, not uninstall and install again.

## Environment requirements

- A cluster with at least one node and a working scheduler.
- `helm` (3.x) on the PATH, with the cluster's kubeconfig in reach.
- Registry access for `nginx` once the broken tag is replaced. The broken tag
  is deliberately unreachable: the pull has to fail, and it must fail with a
  pull error rather than a DNS error that would look like a broken cluster.
- Write access to `/tmp/cka-lab/charts` for the candidate, because the fix
  has to be made on disk and then rolled out with `helm upgrade`.
- No Helm repository needed: the chart is local, so the lab works with no
  network access to a chart index.
