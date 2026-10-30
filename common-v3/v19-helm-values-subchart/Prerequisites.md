# v19 — Overriding a subchart's values: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | `helm` (3.x) on the PATH | the machine | The task is written in Helm's vocabulary — `helm install`, `helm list`, `helm status`, `helm template`. Nothing in the question works without it. |
| 2 | A local parent chart at `/tmp/cka-lab/charts/stack` | `LabSetUp.bash` | The candidate has to install this chart and override its values. It is local on purpose: the lab must not depend on a public repository, on network access, or on what some remote index happens to contain today. |
| 3 | `Chart.yaml` for `stack`, version 1.0.0, with `dependencies:` naming the subchart `backend` 0.1.0 | `LabSetUp.bash` | The parent has to **list** the subchart for it to be part of the chart at all. The `repository:` is a local `file://` path, so the dependency can be materialised without network access. |
| 4 | The subchart vendored under `stack/charts/backend`, with its own `Chart.yaml`, `values.yaml` and templates | `LabSetUp.bash` | This is what `helm dependency update` would have downloaded. It is already there, so the chart renders offline and the candidate never has to touch a chart repository. |
| 5 | The parent's `values.yaml` with a `frontend:` section (image tag `1.0.0`, 1 replica, service port 80) and a `backend:` section (image tag `1.0.0`, 1 replica, service port 8080) | `LabSetUp.bash` | The defaults the candidate has to find and override. The `backend:` section is the part that matters: **a subchart's values live under the subchart's own key in the parent's values file**, and that section overrides the subchart's own `values.yaml`. |
| 6 | The subchart's own `values.yaml` (image tag `1.0.0`, 1 replica, service port 8080) | `LabSetUp.bash` | The subchart's defaults. They sit *under* the parent's `backend:` section in precedence, so the candidate has to know which one wins. |
| 7 | Templates that render a Deployment and a Service for the frontend, and a Deployment and a Service for the backend | `LabSetUp.bash` | The objects the answer is graded on. The backend's templates read `.Values.replicas`, `.Values.image.tag` and `.Values.service.port` — the subchart's own flat keys, not `backend.replicas`. |
| 8 | A pristine copy of the chart at `/tmp/cka-lab/charts/.pristine-stack` | `LabSetUp.bash` | The candidate works on the chart and may edit it. Without a pristine copy the reset could not put the original chart back, and the second attempt would start from the first attempt's edit. |
| 9 | No namespace `apps`, no release `stack`, no `/tmp/cka-lab/stack-values.yaml` | `LabSetUp.bash` | The candidate creates the namespace, writes the values file and installs the release. The setup clears all three so the attempt starts from nothing. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | `/tmp/cka-lab/stack-values.yaml` exists and is not empty | `LabValidate.bash` |
| B | The values file sets the frontend image tag to `2.1.0` | `LabValidate.bash` |
| C | The values file sets the frontend replicas to `3` | `LabValidate.bash` |
| D | The values file sets the backend image tag to `2.0.5` | `LabValidate.bash` |
| E | The values file sets the backend replicas to `2` | `LabValidate.bash` |
| F | The values file sets the backend service port to `9090` | `LabValidate.bash` |
| G | `helm template stack /tmp/cka-lab/charts/stack -f /tmp/cka-lab/stack-values.yaml` renders a frontend Deployment with 3 replicas and the tag `2.1.0` | `LabValidate.bash` |
| H | ... a backend Deployment with 2 replicas and the tag `2.0.5` | `LabValidate.bash` |
| I | ... and a backend Service on port `9090` | `LabValidate.bash` |
| J | A Helm release `stack` in namespace `apps`, with STATUS `deployed` | `LabValidate.bash` |
| K | `helm status stack -n apps` succeeds and reports the release as deployed | `LabValidate.bash` |

## Gotchas

- **A subchart's values live under the subchart's own key in the parent's
  values file.** For a subchart called `backend`, they go under `backend:`:

  ```yaml
  backend:
    image:
      tag: "2.0.5"
    replicas: 2
    service:
      port: 9090
  ```

  The parent has to **list** the subchart in its `dependencies:` for it to be
  part of the chart at all, and `helm dependency update` has to have been
  run to populate `charts/` (in this lab the subchart is vendored there
  already, so no network is needed).

- **`--set backend.replicas=2` overrides the subchart's value.** A `--set`
  key that does *not* start with the subchart's name goes to the **parent**
  chart, which is the classic mistake: `--set replicas=2` sets a `replicas`
  key at the top level of the parent, and the parent has no such key, so
  nothing changes and the backend still runs one replica. The tell is a
  rendered manifest that still says `replicas: 1` for the backend.

- **The parent's `backend:` section wins over the subchart's own
  `values.yaml`.** Both hold `image.tag`, `replicas` and `service.port`. The
  order is: the subchart's own values, then the parent's `backend:` section,
  then `-f`/`--set`. That is why the chart's defaults cannot simply be read
  off the subchart — the parent is what the candidate is editing.

- **The subchart's templates read the subchart's flat keys.** The backend's
  Deployment template says `{{ .Values.replicas }}`, not
  `{{ .Values.backend.replicas }}`: inside a subchart, `.Values` is the
  subchart's own values. The `backend:` prefix only exists in the *parent's*
  values file.

- **A dotted key in a values FILE is a literal key.** In a values file,
  `backend.replicas: 2` creates a key whose name happens to contain a dot —
  Helm does not expand it into a nested map, so it has no effect. The dotted
  form works on the `--set` command line, where Helm splits the key on the
  dots itself. In a values file, write it nested.

- **`helm template` is the check, and it is free.** It renders the chart
  without touching the cluster, so it is the fastest way to see whether the
  values file did what was intended. `helm install` will happily accept a
  values file that changed nothing.

- **The namespace has to exist before the release does.** `helm install -n
  apps` does not create the namespace; it fails with `namespaces "apps" not
  found`.

- **A release name cannot be reused while the old release is still
  installed.** `helm install stack ...` fails with "cannot re-use a name
  that is still in use" if a release called `stack` is still there.
  `helm upgrade` is the way forward in that case.

## Environment requirements

- A cluster with at least one node and a working scheduler.
- `helm` (3.x) on the PATH, with the cluster's kubeconfig in reach.
- Registry access for `nginx` once the release is installed — the chart's
  default repository is `nginx`.
- Write access to `/tmp/cka-lab` for the candidate, because the values file
  has to be written there.
- No Helm repository needed: the chart and its subchart are local, so the
  lab works with no network access to a chart index.
