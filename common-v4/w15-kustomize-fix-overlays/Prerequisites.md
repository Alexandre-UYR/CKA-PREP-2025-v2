# w15 — The overlay that does nothing: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Directory `/tmp/cka-lab/kustomize/base/` | `LabSetUp.bash` | The base every overlay builds on: a Deployment and a Service that both need changing from overlay to overlay. |
| 2 | `base/kustomization.yaml` | `LabSetUp.bash` | Lists `deployment.yaml` and `service.yaml` as the base's resources. Without it, `kubectl kustomize` on the base has nothing to build. |
| 3 | `base/deployment.yaml` — Deployment `app`, 2 replicas, image `nginx:1.24`, labels `app=app` | `LabSetUp.bash` | The object the dev overlay is supposed to change. Its name (`app`) is the one the broken patch gets wrong. |
| 4 | `base/service.yaml` — Service `app` on port 80, selector `app=app` | `LabSetUp.bash` | The Service the prod overlay has to turn into a NodePort, and the thing that tells you the base is complete. |
| 5 | Directory `/tmp/cka-lab/kustomize/overlays/dev/` | `LabSetUp.bash` | The overlay that is broken. It exists so the candidate has something to debug rather than something to write from nothing. |
| 6 | `overlays/dev/kustomization.yaml` — `namespace: dev`, `resources: [../../base]`, `patchesStrategicMerge: [patch-deployment.yaml]` | `LabSetUp.bash` | The overlay definition. The `namespace` is right; the patch reference is where the candidate has to look. |
| 7 | `overlays/dev/patch-deployment.yaml` — a Deployment patch whose `metadata.name` is `worker` | `LabSetUp.bash` | The bug. The base has no resource called `worker`, so the patch matches nothing and never lands. |
| 8 | A pristine copy of the base at `/tmp/cka-lab/kustomize/.pristine-base` | `LabSetUp.bash` | The reset restores the base from it, so a candidate who edited the base to make their patch work does not leave that edit behind. |
| 9 | The `prod` overlay directory left alone by the setup | `LabSetUp.bash` | The setup rebuilds only `overlays/dev`. A `prod` overlay the candidate wrote survives a re-run of the setup. |
| 10 | Namespace `dev` absent | `LabSetUp.bash` | The candidate creates it, so that applying the dev overlay has somewhere to land. |
| 11 | `kubectl` on the machine | the environment | `kubectl kustomize` builds the overlays; it is part of kubectl and needs no separate kustomize binary and no cluster. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | The dev overlay builds | `LabValidate.bash` — `kubectl kustomize` on the dev overlay exits 0 |
| B | The dev overlay builds exactly one Deployment, named `app` | `LabValidate.bash` |
| C | The dev Deployment has 1 replica, image `nginx:1.25`, namespace `dev` | `LabValidate.bash` — the fields are read out of the built YAML |
| D | The prod overlay builds | `LabValidate.bash` — `kubectl kustomize` on the prod overlay exits 0 |
| E | The prod overlay builds a Deployment `app` with 3 replicas and image `nginx:1.26` | `LabValidate.bash` |
| F | The prod overlay builds a Service of type `NodePort` | `LabValidate.bash` |
| G | The dev overlay applied to the cluster | `LabValidate.bash` — Deployment `app` in namespace `dev`, 1 ready replica, image `nginx:1.25`, and the Service beside it |

## Gotchas

- **A patch that names a resource which does not exist in the base does not do
  anything.** Kustomize matches a patch against the resources of the base by
  kind and name, and this patch names a Deployment called `worker` while the
  base calls it `app`. The kustomize built into current kubectl stops the
  build with `no matches for Id Deployment.v1.apps/worker`; older releases
  of kustomize ignored such a patch and printed the base unchanged. The
  build failing is the loud version of the same thing — either way, the
  patch never landed, and the built output still shows `nginx:1.24` and 2
  replicas.

- **A strategic merge patch is matched by kind and name.** The patch said
  `metadata.name: worker`; the base calls the Deployment `app`. The fix is in
  the patch, not in the kustomization.yaml.

- **`kubectl kustomize` is built into kubectl**, so there is no separate
  kustomize binary to install, and it runs without a cluster. `kubectl apply
  -k <dir>` builds the same thing and applies it.

- **The build is the test.** A candidate who writes an overlay and applies it
  straight away has applied something they have not read. `kubectl kustomize`
  prints exactly what would be applied, so it is always cheaper to build
  first.

- **`namespace:` in the kustomization sets the namespace of the built
  objects; it does not create the namespace.** `kubectl apply -k` into a
  namespace that does not exist fails, so `kubectl create namespace dev` is
  part of the job.

- **A strategic merge patch merges lists by their merge key.** The container
  list is merged on `name: app`, so patching the image does not add a second
  container. Writing the patch with a different container name would give the
  Deployment two containers.

- **`patchesStrategicMerge` is the old spelling** of `patches`. Both work.
  `patches` with an explicit `target:` is what lets one overlay patch two
  different kinds — a Deployment and a Service — which is what the prod
  overlay needs.

## Environment requirements

- `kubectl` on the machine running the commands. `kubectl kustomize` needs no
  cluster and no network.
- A cluster with at least one node and registry access for `nginx`, for the
  part where the dev overlay is applied.
- A writable `/tmp` — the base and the overlays live there.
