# c24 — One base, two environments: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | A Kustomize base at `/tmp/cka-lab/kustomize/base` | `LabSetUp.bash` | The task is to build overlays *on top of* a base. Without a base there is nothing to overlay, and the "one base, two environments" idea has no content. |
| 2 | `base/kustomization.yaml` listing `deployment.yaml` and `service.yaml` as resources | `LabSetUp.bash` | A base is only a base if it can be built. The `resources:` list is what makes `kubectl kustomize base` produce a manifest at all. |
| 3 | `base/deployment.yaml`: Deployment `app`, 2 replicas, image `nginx:1.24`, labels `app: app` | `LabSetUp.bash` | It is the object the overlays have to change: the image and the replica count are both wrong for the environments the task asks for. |
| 4 | `base/service.yaml`: Service `app` on port 80, selector `app: app` | `LabSetUp.bash` | The base has to be a realistic base: an overlay that carries the whole stack, not just the Deployment. It also shows that an overlay changes only what it patches. |
| 5 | An empty `overlays` directory at `/tmp/cka-lab/kustomize/overlays` | `LabSetUp.bash` | The place the candidate's work goes. The setup never fills it and never empties it - it only creates it when it is missing, so a re-run cannot wipe an attempt that is in progress. |
| 6 | `kubectl` with the built-in Kustomize (`kubectl kustomize`) | the machine | The task says to build the overlays; `kubectl kustomize` is the built-in way to do that, and it is what the grader uses to read the overlays back. |
| 7 | A cluster the dev overlay can be applied to | the cluster itself | The task asks for the dev overlay to be *applied*, and the grader checks the result in the cluster. The base carries no namespace, so the overlay lands in the current namespace unless the candidate puts a namespace in the overlay. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | `/tmp/cka-lab/kustomize/overlays/dev/kustomization.yaml`, referencing the base | `LabValidate.bash` |
| B | `/tmp/cka-lab/kustomize/overlays/prod/kustomization.yaml`, referencing the base | `LabValidate.bash` |
| C | The dev overlay builds a Deployment `app` with exactly 1 replica | `LabValidate.bash` |
| D | The dev overlay builds a Deployment `app` with image `nginx:1.25` | `LabValidate.bash` |
| E | The prod overlay builds a Deployment `app` with exactly 3 replicas | `LabValidate.bash` |
| F | The prod overlay builds a Deployment `app` with image `nginx:1.26` | `LabValidate.bash` |
| G | In the cluster, a Deployment `app` with 1 replica, 1 ready replica and image `nginx:1.25` - the dev overlay applied | `LabValidate.bash` |

## Gotchas

- **`kubectl kustomize` is built into kubectl.** There is nothing to install:
  the standalone `kustomize` binary is a convenience, not a dependency. Any
  answer that needs a second tool to be downloaded is solving a problem the
  question does not have. (The standalone binary renders the same result, so
  `kustomize build` is an equally good way to build the overlays - the grader
  reads them back with `kubectl kustomize`.)

- **An overlay refers to the base with a relative path**: `resources:
  - ../../base`. The path is resolved from the overlay's own directory, so
  `../../base` from `/tmp/cka-lab/kustomize/overlays/dev` is
  `/tmp/cka-lab/kustomize/base`. A path like `base` or `../base` points
  somewhere else and the build fails with "no such file or directory".

- **A patch that names the wrong kind or the wrong name does nothing, and
  the build still succeeds.** This is the trap in the question. A strategic
  merge patch has to say what it is patching:
  `apiVersion: apps/v1`, `kind: Deployment`, `metadata.name: app`. Write
  `kind: Deployment` but `name: nginx`, or patch a `DeploymentConfig`, or
  leave out `metadata.name`, and Kustomize finds nothing to merge - no error,
  no warning, and the built manifest still carries `nginx:1.24` and 2
  replicas. The overlay "works" and changes nothing.

- **The same applies to the `replicas:` and `images:` transformers.** They
  are the tidier way to do this and they are fussy in the same way:
  `replicas: - name: app  count: 1` has to name the Deployment `app` exactly,
  and `images: - name: nginx  newTag: "1.25"` has to match the image *name*
  (`nginx`), not the whole reference (`nginx:1.24`).

- **The built output is what counts, not the overlay files.** An overlay that
  produces the right manifest is right; an overlay that *looks* right but
  builds the base unchanged is wrong. Build it and read the output:
  `kubectl kustomize /tmp/cka-lab/kustomize/overlays/dev`.

- **The dev and the prod overlays are independent of each other.** The prod
  overlay is not applied to the cluster - it is only built. The cluster ends
  up with the dev overlay's manifest: 1 replica of `nginx:1.25`.

- **The base is shared and the overlays must not edit it.** Changing
  `base/deployment.yaml` to make one overlay come out right changes the other
  overlay too, and the grader reads the base and both overlays separately.

- **Applying an overlay is `kubectl apply -k <dir>`.** It reads the
  `kustomization.yaml` in that directory and applies what it builds. The
  same directory can also be built with `kubectl kustomize <dir>` and piped
  into `kubectl apply -f -`.

## Environment requirements

- `kubectl` on the PATH, new enough to have `kubectl kustomize` built in
  (1.14 or later).
- A cluster with at least one node and a working scheduler, reachable with
  the current kubeconfig.
- Registry access for `nginx:1.25`, the image the dev overlay asks for.
- Write access to `/tmp/cka-lab/kustomize/overlays` for the candidate.
- No standalone `kustomize` binary required.
