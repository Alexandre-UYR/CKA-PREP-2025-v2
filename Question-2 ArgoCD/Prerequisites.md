# Q2 — Argo CD: prerequisite inventory

The task is a "generate, don't install" question. Nothing in Argo CD is ever
applied to the cluster: you produce a manifest with `helm template` and save it
to a file. The only cluster state that has to exist before you start is the
Argo CD **CRDs**, because the task says they are pre-installed and the chart
must not install them a second time.

## Prerequisite inventory

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | The Argo CD CRDs (`applications.argoproj.io`, `appprojects.argoproj.io`, `applicationsets.argoproj.io`, ...) | LabSetUp.bash | The task says the CRDs are "pre installed" and that the chart must not install them. The setup applies the upstream CRD manifests so the pre-state is real, not just claimed. |
| 2 | Those CRDs are **cluster-scoped** | Argo CD upstream | They are not tied to a namespace, so no namespace has to exist for them, and deleting them would destroy every Argo CD resource of that type in the cluster. That is why the reset leaves them alone. |
| 3 | Nothing else from the Argo CD chart | - | The task never asks for an installation. There is no `argocd` namespace and no Argo CD workload in the pre-state; the namespace is one of the things you have to create. |
| 4 | A `helm` client with a writable config and cache | Environment | The answer is produced by `helm repo add` + `helm template`. Without helm the question cannot be done. |
| 5 | Network access to `https://argoproj.github.io/argo-helm` | Environment | `helm repo add` downloads the repository index, and `helm template argocd argocd/argo-cd` resolves the chart from it. |
| 6 | Write access to `/root` | Environment | The generated manifest has to land in `/root/argo-helm.yaml`. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| 1 | Helm repo named `argocd` pointing at `https://argoproj.github.io/argo-helm` | `LabValidate.bash`: "Helm repo 'argocd' points at https://argoproj.github.io/argo-helm" |
| 2 | Namespace `argocd` | `LabValidate.bash`: "Namespace argocd exists" |
| 3 | `/root/argo-helm.yaml`, non-empty | `LabValidate.bash`: "/root/argo-helm.yaml exists", "/root/argo-helm.yaml is not empty" |
| 4 | The manifest generated from chart `argo-cd` version `7.7.3` with `--set crds.install=false` | `LabValidate.bash`: "The generated manifest contains no CustomResourceDefinition", "contains the argocd-server workload", "contains a Deployment" |
| 5 | Every namespaced object in the manifest in the `argocd` namespace | `LabValidate.bash`: "Every namespaced object in the manifest is in the argocd namespace", "The manifest places objects in the argocd namespace" |

## Gotchas

- **The chart's CRDs live in `templates/crds/`, not in a `crds/` directory.**
  That matters: CRDs in a chart's `crds/` directory are skipped by `helm
  template` altogether, but these are regular templates guarded by
  `{{- if .Values.crds.install }}`. So `helm template` really does print the
  CRDs by default, and `--set crds.install=false` really does remove them. The
  grader counts `kind: CustomResourceDefinition` in the file and expects zero.
- **`helm repo add` is not enough.** `helm template argocd argocd/argo-cd`
  resolves `argocd/argo-cd` as *repo/chart*, so the repo has to be there and
  its index downloaded (`helm repo update`).
- **`--namespace argocd` sets the namespace on the rendered objects**, it does
  not create it. Create the namespace separately, as the task says.
- **The version is part of the answer:** chart `7.7.3` (which ships Argo CD
  v2.11.x). `--version 7.7.3` pins it; without it you get whatever is newest.
- **The manifest is only TEMPLATED, not applied.** The task never asks for an
  installation, so the grader deliberately does *not* look for running Argo CD
  pods, a `argocd-server` Service, or an `argocd-config` Secret in the
  cluster. Only the file is graded.
- **Cluster-scoped objects carry no namespace.** The chart also renders
  ClusterRoles and ClusterRoleBindings; they have no `namespace:` field at all,
  and their `subjects:` entries point at `namespace: argocd`. The grader only
  fails if some object names a namespace *other than* `argocd`.
- **Do not delete the CRDs.** They are pre-installed state and they are
  cluster-scoped: removing one wipes every Argo CD resource of that type. The
  reset leaves them in place on purpose.

## Environment requirements

- `helm` installed and on `PATH` (`helm version` should work).
- Network access to `https://argoproj.github.io/argo-helm` (chart download) and
  to `https://raw.githubusercontent.com` (the setup installs the CRDs from there).
- A cluster where `kubectl` is configured and CRDs can be installed
  (cluster-admin-ish rights: CRDs are cluster-scoped).
- Write access to `/root`, and the lab must run as a user who can write there
  (root in the Killercoda playground).
