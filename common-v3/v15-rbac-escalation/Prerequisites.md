# v15 — The permission that lets you grant yourself permissions: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `esc` | `LabSetUp.bash` | The ServiceAccount, the Role and the RoleBinding live here, and the task names the namespace. |
| 2 | ServiceAccount `helper` | `LabSetUp.bash` | The subject of the task. It is the identity whose permissions have to be examined and then trimmed. |
| 3 | Role `helper-role` granting `get` and `list` on `pods` | `LabSetUp.bash` | The legitimate half of the Role. It is what the ServiceAccount is supposed to be allowed to do, and it has to survive the fix. |
| 4 | The same Role granting `escalate` and `bind` on `roles` | `LabSetUp.bash` | The hole. `escalate` means "you may create or update a Role granting permissions you do not hold yourself"; `bind` means "you may bind a Role to a ServiceAccount you do not control". Together they turn a read-only ServiceAccount into one that is effectively namespace-admin: it can write itself a Role granting it anything in the namespace, and hand that Role to anyone else in there. |
| 5 | RoleBinding `helper-binding` binding `helper-role` to `helper` | `LabSetUp.bash` | Without the binding the Role grants nobody anything and there is nothing to prove. The binding is what makes `kubectl auth can-i --as=system:serviceaccount:esc:helper` answer for this Role. |
| 6 | The ServiceAccount is bound to nothing else that grants it pod permissions | `LabSetUp.bash` creates only this binding | The validator asks the API server whether the ServiceAccount can list pods. If another binding granted it that, the check would pass for the wrong reason. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | The Role `helper-role` still exists in namespace `esc` | `LabValidate.bash` |
| B | It still grants `get` on `pods` | `LabValidate.bash` |
| C | It still grants `list` on `pods` | `LabValidate.bash` |
| D | No rule of the Role grants `escalate` | `LabValidate.bash` |
| E | No rule of the Role grants `bind` | `LabValidate.bash` |
| F | No rule of the Role uses the wildcard verb `*` | `LabValidate.bash` |
| G | `kubectl auth can-i escalate roles --as=system:serviceaccount:esc:helper -n esc` answers `no` | `LabValidate.bash` |
| H | `kubectl auth can-i bind roles --as=system:serviceaccount:esc:helper -n esc` answers `no` | `LabValidate.bash` |
| I | `kubectl auth can-i create pods --as=system:serviceaccount:esc:helper -n esc` answers `no` | `LabValidate.bash` |
| J | `kubectl auth can-i list pods --as=system:serviceaccount:esc:helper -n esc` still answers `yes` | `LabValidate.bash` |

## Gotchas

- **`kubectl auth can-i` exits non-zero when the answer is "no".** Testing
  its exit status tells you nothing; the answer is on stdout. Pipe it:
  `kubectl auth can-i ... | tail -n 1 | tr -d '[:space:]'`. The validator
  does exactly this. (The "yes" answer is printed with a newline and the
  "no" answer is not, which is another reason not to parse it by hand.)

- **The resource name is resolved for you.** `kubectl auth can-i escalate
  roles` resolves `roles` through discovery to
  `rbac.authorization.k8s.io/roles`, so it matches the rule in the Role. If
  you write the rule by hand and forget the API group, the probe will answer
  "no" and you will think the hole is closed when it is not.

- **The verbs to look for are `escalate` and `bind`, not `create` and
  `update`.** `escalate` is a special verb: it is checked when a Role or
  RoleBinding is written, and it lets the writer grant permissions they do
  not hold themselves. `bind` is its partner for RoleBindings. Neither one
  shows up in a Role that grants normal verbs, so a candidate looking only
  at the "sensible" verbs can miss them entirely.

- **`escalate` on its own is an admission-time check, not a grant.** The
  RBAC authorizer matches verbs literally, so a ServiceAccount holding
  `escalate` on roles is not automatically allowed to create pods. What
  `escalate` does is let it WRITE a Role with any rules it likes, and what
  `bind` does is let it attach such a Role to another ServiceAccount. The
  point of the exercise is that those two verbs have no place in a
  read-only Role.

- **Do not delete the Role.** The task says the Role must still let the
  ServiceAccount read pods. Deleting it and letting the ServiceAccount fall
  back to nothing passes "can-i create pods → no" but fails "can-i list pods
  → yes" and fails the "still grants get and list" checks.

- **Do not use a wildcard to tidy up.** Replacing the rules with
  `verbs: ["*"]` would grant the ServiceAccount everything in the namespace.
  The validator looks for the `*` verb in every rule of the Role.

- **Watch the API group on the Role rule.** The rule that carries `escalate`
  and `bind` is on `roles` in the `rbac.authorization.k8s.io` group, while
  the rule that carries `get` and `list` is on `pods` in the core group
  (`apiGroups: [""]`). Mixing them up produces a Role that grants nothing
  useful and still exposes the escalation verbs.

## Environment requirements

- A cluster with at least one node and `kubectl` in the current context.
- The account running `kubectl` must be allowed to create
  SelfSubjectAccessReviews, which it is for a cluster administrator.
- RBAC enabled (it is by default; the `kubernetes.io/enable-rbac` flag must
  not be set to `false`).
- No special components: this is plain Role and RoleBinding plumbing.
