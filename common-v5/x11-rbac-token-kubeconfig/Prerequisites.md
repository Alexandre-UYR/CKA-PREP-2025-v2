# x11 — Prove it with the credentials: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `rbac` | `LabSetUp.bash` | The Role, the RoleBinding and the ServiceAccount all live here, and the task names the namespace. The namespace is re-created on every run, so a Role or RoleBinding left behind by a previous attempt does not survive. |
| 2 | ServiceAccount `admin` | `LabSetUp.bash` | The identity the whole question is about. It starts with no permissions at all. |
| 3 | No Role and no RoleBinding in the namespace | the setup's absence of them | The pre-state is "a ServiceAccount that can do nothing". |
| 4 | No token Secret for the ServiceAccount | Kubernetes 1.24 and later | Since 1.24 the API server does not create a long-lived token Secret for a ServiceAccount. The token has to be minted on demand, which is the second half of the task. |
| 5 | No `/root/rbac.kubeconfig` | the setup removes it | The kubeconfig is the candidate's output. A leftover would make the exercise look solved before it is. |
| 6 | The `default` namespace, present and empty | the cluster | It is the namespace the boundary is proved against: the same credentials must fail there. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | A Role in namespace `rbac` granting `list` on `pods`, and no other verb, no other resource, no wildcard | `LabValidate.bash` |
| B | A RoleBinding in namespace `rbac` binding that Role to the ServiceAccount `admin` | `LabValidate.bash` |
| C | `kubectl auth can-i list pods --as=system:serviceaccount:rbac:admin -n rbac` answers yes, and `-n default` answers no | `LabValidate.bash` |
| D | `/root/rbac.kubeconfig` exists, names a context, and names the ServiceAccount it carries | `LabValidate.bash` |
| E | `kubectl --kubeconfig /root/rbac.kubeconfig auth can-i list pods -n rbac` answers yes, and `-n default` answers no | `LabValidate.bash` |
| F | The kubeconfig can actually list pods in `rbac`, and cannot list them in `default` | `LabValidate.bash` (live) |

## Gotchas

- **Since Kubernetes 1.24 there are no long-lived ServiceAccount tokens stored
  as Secrets.** The API server does not create a token Secret for a
  ServiceAccount any more, and `kubectl create token` mints a short-lived
  token on demand instead. That is the token that goes into the kubeconfig —
  `kubectl create token admin -n rbac`. The old habit of looking for a Secret
  of type `kubernetes.io/service-account-token` finds nothing.

- **A RoleBinding is namespaced.** It grants the ServiceAccount access inside
  its own namespace and nowhere else. That is exactly what the `default` probe
  demonstrates: the same credentials that list pods in `rbac` are refused in
  `default`. A ClusterRole and a ClusterRoleBinding would answer yes in both
  namespaces, and the grader catches that.

- **The Role has to grant `list` on `pods` and nothing else.** A rule with
  `verbs: ["*"]`, or with `resources: ["*"]`, or a rule that also grants
  `secrets`, is refused by the grader even though it lets the candidate list
  pods.

- **The identity the API server sees is `system:serviceaccount:<namespace>:<name>`.**
  That is the string `kubectl auth can-i --as=` needs, and it is the string
  the API server will name when it refuses a request made with the candidate's
  own kubeconfig.

- **`kubectl auth can-i` exits non-zero when the answer is "no".** A script that
  checks the exit code rather than the output will read a correct "no" as a
  failure. The validator reads the output and throws the exit code away.

- **The kubeconfig needs a cluster as well as credentials.** A context with a
  token but no server and no certificate authority points at nothing. The
  easiest way to get both right is to copy the current kubeconfig and add a
  user and a context to the copy.

- **The token expires.** `kubectl create token` issues a token that is good for
  an hour by default. The kubeconfig is worth checking while it is still
  fresh, and `--duration` makes it longer.

## Environment requirements

- A cluster with at least one node.
- The candidate must be able to create Roles, RoleBindings and ServiceAccount
  tokens, and to impersonate a ServiceAccount with `kubectl auth can-i --as`.
  In practice that means cluster-admin.
- `kubectl` 1.24 or later, for `kubectl create token`.
