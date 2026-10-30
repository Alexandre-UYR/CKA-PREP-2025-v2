# c19 — A Role bound to a ServiceAccount: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `audit` | `LabSetUp.bash` | The task places the Role and the RoleBinding in this namespace. A Role is namespaced, so the namespace has to exist first. |
| 2 | ServiceAccount `auditor` in `audit` | `LabSetUp.bash` | This is the identity the Role is bound to. `kubectl auth can-i --as=system:serviceaccount:audit:auditor` asks the question from exactly this identity, so the ServiceAccount has to exist and the binding subject has to name it. |
| 3 | No Role `pod-reader` and no RoleBinding `pod-reader-binding` | absent by design | The task is to create both. A pre-existing grant would make the third probe (the one in another namespace) pass or fail for reasons the candidate did not create. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | Role `pod-reader` in namespace `audit` | `LabValidate.bash` |
| B | Its rules grant exactly `get`, `list` and `watch` - no other verb, no wildcard | `LabValidate.bash` (`.rules[*].verbs[*]`) |
| C | Its rules name exactly the resource `pods` | `LabValidate.bash` (`.rules[*].resources[*]`) |
| D | Its rules apply to the core API group | `LabValidate.bash` (`.rules[*].apiGroups[*]`) |
| E | RoleBinding `pod-reader-binding` in namespace `audit` | `LabValidate.bash` |
| F | Its `roleRef` has kind `Role` and names `pod-reader` | `LabValidate.bash` |
| G | Its subjects include the ServiceAccount `auditor` in namespace `audit` | `LabValidate.bash` |
| H | `kubectl auth can-i list pods --as=system:serviceaccount:audit:auditor -n audit` answers `yes` | `LabValidate.bash` |
| I | `kubectl auth can-i delete pods --as=system:serviceaccount:audit:auditor -n audit` answers `no` | `LabValidate.bash` |
| J | `kubectl auth can-i list pods --as=system:serviceaccount:audit:auditor -n default` answers `no` | `LabValidate.bash` |

## Gotchas

- **A RoleBinding in a namespace only grants access WITHIN that namespace.**
  That is why the third probe - the same `list pods` check in a different
  namespace - answers `no`. That is the point of namespaced RBAC: a Role plus
  a RoleBinding is a scoped grant, and the namespace is the scope. A grader
  that checked only the first probe would not notice a candidate who had bound
  a ClusterRole instead, which would grant access everywhere.

- **Binding a Role to a ServiceAccount only takes effect for pods that use
  that ServiceAccount** (via `serviceAccountName` in the pod spec). It does
  not change anyone's own permissions: binding the Role to
  `system:serviceaccount:audit:auditor` does not let *you* list pods, and it
  does not let the auditor list pods until something actually runs as that
  ServiceAccount.

- **Pods are in the core API group, so `apiGroups` is the empty string.** In
  YAML that is `apiGroups: [""]` - not `"core"`, not `"v1"`, and not
  `"apps"`. The API server accepts `""` and rejects the other two.

- **The `roleRef` of a RoleBinding must have kind `Role`.** A RoleBinding
  pointing at a ClusterRole is rejected by the API server, and a ClusterRole
  cannot be scoped to a namespace the way a Role can.

- **The subject's namespace has to be written out.** A RoleBinding in
  namespace `audit` whose subject is `ServiceAccount auditor` with no
  namespace field is rejected - the API server has no namespace to default
  the subject to, because a RoleBinding can bind subjects from anywhere.

- **`kubectl auth can-i` exits 1 when the answer is `no`.** A script that runs
  it under `set -e` stops there and mistakes the refusal for a failure of the
  command.

- **Watch out for `resources: ["*"]`.** It reads as "pods" but grants every
  resource in the core group, including `secrets` and `configmaps`. The task
  says pods and nothing else.

## Environment requirements

- A cluster with at least one node.
- `kubectl` configured against that cluster with permission to create Roles,
  RoleBindings and to run `kubectl auth can-i`.
- The `default` namespace must exist: it is used as the "different namespace"
  for the third probe.
- No controller, no admission webhook, nothing else to install - this question
  is purely about RBAC objects.
