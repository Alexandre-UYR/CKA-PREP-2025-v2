# w10 — Install a chart, and install it differently: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | `helm` (3.x) on the PATH | the machine | The task is written in Helm's vocabulary — `helm install`, `helm list`, `helm status`, `helm template`. Nothing in the question works without it. If helm is missing the setup says so and creates nothing. |
| 2 | A local chart at `/tmp/cka-lab/charts/hello-world` | `LabSetUp.bash` | The chart the candidate installs. It is local on purpose: the lab must not depend on a public repository, on network access, or on what some remote index happens to contain today. |
| 3 | `Chart.yaml` — name `hello-world`, version `1.0.0`, appVersion `1.25.0` | `LabSetUp.bash` | The chart's identity. Helm reads it before it does anything else, and the release records it. |
| 4 | The chart's `values.yaml` — `replicaCount: 1`, `image: nginx:1.25` | `LabSetUp.bash` | The two values the templates read. `replicaCount` is the key the candidate has to override from outside the chart; `image` is the key they do not, and the rendered Deployment has to keep it. |
| 5 | `templates/deployment.yaml` — renders a Deployment named `hello-world` with `replicas: {{ .Values.replicaCount }}` and `image: "{{ .Values.image }}"`, labelled `app.kubernetes.io/instance: {{ .Release.Name }}` | `LabSetUp.bash` | The object the answer is graded on. It reads the replica count from the values, which is what makes an external values file able to change it. |
| 6 | `templates/service.yaml` — renders a Service named `hello-world` selecting the same pods | `LabSetUp.bash` | The second object the chart produces. It is not graded directly, but a chart that renders a Deployment without a Service is an incomplete answer to "install a chart". |
| 7 | A pristine copy of the chart at `/tmp/cka-lab/charts/.pristine-hello-world` | `LabSetUp.bash` | The candidate may edit the chart. Without a pristine copy the reset could not put the original chart back, and the second attempt would start from the first attempt's edit. The validator compares the two. |
| 8 | No namespace `apps`, no release `hello`, no `/root/hello-values.yaml` | `LabSetUp.bash` | The candidate creates all three. The setup clears them so the attempt starts from nothing — in particular a release left over from a previous attempt would make `helm install hello` fail. |
| 9 | A writable `/root` on the machine running `kubectl` | the environment | The values file has to be written to `/root/hello-values.yaml`. If `/root` is not writable the candidate cannot produce an answer at all. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | Namespace `apps` exists | `LabValidate.bash` |
| B | `/root/hello-values.yaml` exists, is not empty, and sets `replicaCount` to `3` | `LabValidate.bash` |
| C | The chart on disk still matches the pristine copy — the chart was not edited | `LabValidate.bash` |
| D | `helm template hello /tmp/cka-lab/charts/hello-world -f /root/hello-values.yaml` renders a Deployment with 3 replicas and the image `nginx:1.25` | `LabValidate.bash` |
| E | A Helm release `hello` in namespace `apps`, with status `deployed` | `LabValidate.bash` |
| F | The Deployment the release manages has 3 replicas, 3 of them ready | `LabValidate.bash` |
| G | ... and runs the image `nginx:1.25` | `LabValidate.bash` |

## Gotchas

- **`helm template` renders the chart without touching the cluster, and that is
  the safe way to check what a chart will produce.** It creates no release, it
  writes nothing, and it is free to run as often as you like. Read the
  rendered output before you install, not after.

- **A values FILE is a YAML document, and `replicaCount: 3` is a key in it.**
  The chart's template reads `{{ .Values.replicaCount }}`, so the file has to
  hold that key at the top level, written the way YAML nests a mapping. The
  flattened form `replicaCount=3` belongs to the command line —
  `--set replicaCount=3` — where Helm splits the key on the dots itself. The
  two are **not interchangeable in a file**: a values file containing
  `replicaCount=3` is a document with one key whose name happens to contain
  an `=`, the chart does not read it, and nothing changes.

- **A release name cannot be reused while the old release is still installed.**
  `helm install hello ...` a second time fails with "cannot re-use a name that
  is still in use". Once the release is there, the way to change its values is
  `helm upgrade hello ... -f <file>`, or `helm upgrade --install` to do both
  steps in one command.

- **`helm install` accepts a values file that changed nothing.** There is no
  error and no warning; the install succeeds and the Deployment still has one
  replica. The rendered output is where that shows up, which is why
  `helm template` comes before the install.

- **The namespace has to exist before the release does.** `helm install -n
  apps` does not create the namespace; it fails with `namespaces "apps" not
  found`.

- **A values file overrides the chart's `values.yaml`; it does not replace
  it.** The chart's own `values.yaml` still supplies `image: nginx:1.25`,
  which is why the file only needs the one key the candidate wants to change.
  Overriding one key does not blank out the others.

- **Editing the chart is the wrong answer even when the end state looks right.**
  The task asks for the replica count to come from a values file, and the
  validator compares the chart on disk with the pristine copy the setup kept.

## Environment requirements

- A cluster with at least one node and a working scheduler.
- Registry access for `nginx:1.25`, once the release is installed — the
  graded check is 3 *ready* replicas, not 3 created ones.
- `helm` (3.x) on the PATH, with the cluster's kubeconfig in reach.
- Write access to `/root` for the candidate and for the validator.
- No Helm repository needed: the chart is local, so the lab works with no
  network access to a chart index.
