# c22 — Define a CRD and use it: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `custom` | `LabSetUp.bash` | The task creates the Widget in this namespace. It has to exist before the custom resource can be created in it. |
| 2 | The directory `/tmp/cka-lab`, empty | `LabSetUp.bash` | The task asks the candidate to save their CRD manifest to `/tmp/cka-lab/c22.crd.yaml`. The directory has to exist for that to be possible, and the setup clears any manifest left behind by a previous attempt. |
| 3 | No `widgets.example.com` CRD and no Widgets | `LabSetUp.bash` | The task is to *define* the CRD, so the pre-state must not contain one. The setup deletes any CRD left over from a previous attempt, which also removes every Widget it owned. |
| 4 | A cluster whose API server has `apiextensions.k8s.io/v1` enabled | the cluster itself | CRDs and the `apiextensions.k8s.io/v1` API are enabled by default on every current Kubernetes release. Nothing has to be installed. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | A CRD named `widgets.example.com` | `LabValidate.bash` |
| B | `spec.group: example.com` | `LabValidate.bash` |
| C | `spec.names.kind: Widget`, `plural: widgets`, `singular: widget` | `LabValidate.bash` |
| D | `spec.scope: Namespaced` | `LabValidate.bash` |
| E | A served version `v1` | `LabValidate.bash` |
| F | A schema whose `spec` property requires `size`, typed as a string | `LabValidate.bash` |
| G | The CRD manifest saved to `/tmp/cka-lab/c22.crd.yaml` | the reset removes it; the grader reads the CRD from the cluster |
| H | A Widget `w1` in namespace `custom` with `spec.size: large` | `LabValidate.bash` |
| I | `kubectl get widgets` works and lists the Widget | `LabValidate.bash` |

## The shape of the CRD

```
widgets.example.com
  group: example.com
  scope: Namespaced
  names:
    plural: widgets       <- what "kubectl get widgets" uses
    singular: widget
    kind: Widget          <- the kind you write in a manifest
  versions:
    - name: v1            <- the version you write as apiVersion example.com/v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:  <- the structural schema
          type: object
          properties:
            spec:
              type: object
              required: [size]     <- the required list lives HERE
              properties:
                size:
                  type: string
```

## Gotchas

- **The plural in `names` is what makes `kubectl get widgets` work.** The API
  server registers the new resource under the *plural* name, not the kind.
  `kind: Widget` with `plural: gadgets` gives you `kubectl get gadgets` and
  an `apiVersion` of `example.com/v1` on a kind called `Widget`. Get the
  plural wrong and the resource is created fine but is unreachable under the
  name the task asks for.

- **A CRD without an `openAPIV3Schema` is rejected.** With
  `preserveUnknownFields: false` — which is the default for
  `apiextensions.k8s.io/v1` — the API server refuses a CRD whose version has
  no structural schema. The error names the missing field, for example
  `spec.versions[0].schema.openAPIV3Schema: Required value`. A structural
  schema means every field has to be declared; you cannot leave a subtree
  open.

- **The `required` list belongs to the `spec` property, not to the top of the
  CRD schema.** This is the mistake that looks right and is wrong:

  ```
  openAPIV3Schema:
    type: object
    required: [size]          # WRONG - there is no top-level "size"
    properties:
      spec:
        type: object
        properties:
          size:
            type: string
  ```

  The correct place is inside `properties.spec.required`, because it is the
  *spec object* that has to carry `size`. A `required` list at the top level
  refers to top-level fields of the custom resource — `apiVersion`, `kind`,
  `metadata` and `spec` — and a top-level `required: [size]` is a schema
  error in its own right.

- **`spec.size` has to be a string.** `type: string` means the value is
  `"large"`, not `large`. An unquoted `large` in YAML is a string anyway, but
  `size: 5` against `type: string` is rejected by the API server, and so is a
  value the schema does not allow.

- **The CRD takes a moment to be served.** After `kubectl apply`, the API
  server has to set up the new endpoint before `kubectl get widgets` works.
  `kubectl get crd widgets.example.com` shows `Established` in
  `STATUS.conditions` once it is ready; until then `kubectl get widgets`
  fails with `the server doesn't have a resource type "widgets"`. Waiting on
  the CRD's `Established` condition is the reliable way to avoid that race.

- **Deleting the CRD deletes the custom resources.** The CRD has a cleanup
  finalizer: when it is deleted, every Widget it owned is deleted with it.
  That is why the reset only has to remove the CRD.

- **A CRD is cluster-scoped, its resources are not.** The CRD object itself
  has no namespace; `scope: Namespaced` is what decides that a Widget lives
  in a namespace and is addressed as `widgets/w1` inside `custom`.

## Environment requirements

- A cluster with at least one node (not strictly needed for a CRD, but the
  task creates a Pod-shaped resource and expects the API to serve it).
- The `apiextensions.k8s.io/v1` API enabled (the default).
- No controller, no operator and no `kubectl` plugin: a CRD on its own adds a
  new kind to the API server and nothing more. Reconciling Widgets is
  somebody else's problem.
