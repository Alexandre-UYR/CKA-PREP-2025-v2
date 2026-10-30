# c18 — A ClusterRole that grants exactly one verb: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `ops` | `LabSetUp.bash` | The task names the namespace the ServiceAccount lives in, and the binding subject has to point at it. |
| 2 | ServiceAccount `builder` in `ops` | `LabSetUp.bash` | This is the identity the ClusterRole is bound to. `kubectl auth can-i --as=system:serviceaccount:ops:builder` asks the question from exactly this identity, so the ServiceAccount has to exist and the binding has to name it. |
| 3 | No ClusterRole `workload-creator` and no ClusterRoleBinding `builder-workloads` | absent by design | The task is to create both. The grader reads their rules, so a pre-existing object would make the question unanswerable. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | ClusterRole `workload-creator` | `LabValidate.bash` |
| B | Its rules grant the single verb `create` - no `*`, no `delete`, no `get`, nothing else | `LabValidate.bash` (`.rules[*].verbs[*]`) |
| C | Its rules name exactly `deployments`, `statefulsets` and `daemonsets` - no wildcard resource | `LabValidate.bash` (`.rules[*].resources[*]`) |
| D | Its rules apply to the `apps` API group | `LabValidate.bash` (`.rules[*].apiGroups[*]`) |
| E | ClusterRoleBinding `builder-workloads` | `LabValidate.bash` |
| F | Its `roleRef` names the ClusterRole `workload-creator` | `LabValidate.bash` |
| G | Its subjects include the ServiceAccount `builder` in namespace `ops` | `LabValidate.bash` |
| H | `kubectl auth can-i create deployments --as=system:serviceaccount:ops:builder` answers `yes` | `LabValidate.bash` |
| I | `kubectl auth can-i delete deployments --as=system:serviceaccount:ops:builder` answers `no` | `LabValidate.bash` |

## Gotchas

- **A ClusterRole is cluster-scoped, so a ClusterRoleBinding is what binds a
  namespaced ServiceAccount to it.** A RoleBinding cannot reference a
  ClusterRole: the API server rejects the object, because a RoleBinding in
  namespace `ops` can only grant a Role that also lives in `ops`. The
  ClusterRoleBinding has to be cluster-scoped and its subject has to name the
  namespace explicitly, because there is no other namespace to default to.

- **The `can-i` probe is the real proof.** The object can look exactly right
  and still not grant what you think, because the API group has to match too.
  `deployments` live in the `apps` group, not in the core group. A rule
  written as `apiGroups: [""]` with `resources: ["deployments"]` matches
  nothing at all, and `can-i create deployments` will answer `no` while the
  YAML still looks plausible. This is the single most common way to get this
  question wrong.

- **`verbs: ["*"]` grants everything, not everything you meant.** The task
  says exactly one verb, so `create` has to be spelled out. The same goes for
  `resources: ["*"]` - a wildcard resource plus a single verb is still a
  grant on every resource in the group.

- **`kubectl auth can-i` with `--as` does not need a token.** It sends a
  SubjectAccessReview with the given user name and groups. It answers the
  authorization question without anything actually running as that
  ServiceAccount, which is exactly why it is the right probe here.

- **A ClusterRoleBinding is cluster-wide, so the grant applies in every
  namespace.** That is the point of the `apps` group here: a ClusterRole
  cannot be narrowed to one namespace. If the work needs to stay inside `ops`,
  the answer is a Role plus a RoleBinding instead.

- **`kubectl auth can-i` exits 1 when the answer is `no`.** A script that runs
  it under `set -e` will stop there and mistake the refusal for a failure of
  the command.

## Environment requirements

- A cluster with at least one node.
- `kubectl` configured against that cluster with permission to create
  ClusterRoles, ClusterRoleBindings and to run `kubectl auth can-i`.
- No controller, no ingress, nothing else to install: this question is purely
  about RBAC objects.
