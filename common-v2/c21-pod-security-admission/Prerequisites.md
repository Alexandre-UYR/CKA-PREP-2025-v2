# c21 — Enforce the restricted Pod Security Standard: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `psa-test`, with no `pod-security.kubernetes.io/*` labels on it | `LabSetUp.bash` | The task is about labelling this namespace, so it has to exist and has to start out *unlabelled*. The setup removes and recreates the namespace, so a re-run takes back whatever the candidate labelled it with and drops the Pods they left inside. |
| 2 | A cluster running the kube-apiserver with Pod Security Admission enabled | the cluster itself | Pod Security Admission is built into the API server and is on by default on every current release. There is nothing to install and no controller to deploy — the namespace labels are what switch it on. |
| 3 | A cluster with a working scheduler and a node that can run `busybox:stable` | the cluster itself | The compliant Pod has to start, not just be accepted by the API server. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | The label `pod-security.kubernetes.io/enforce=restricted` on namespace `psa-test` | `LabValidate.bash` |
| B | Pod `compliant` in namespace `psa-test` | `LabValidate.bash` |
| C | The Pod is Running and Ready | `LabValidate.bash` |
| D | `runAsNonRoot: true` | `LabValidate.bash` |
| E | A `runAsUser` that is present and not 0 | `LabValidate.bash` |
| F | `allowPrivilegeEscalation: false` on the container | `LabValidate.bash` |
| G | Seccomp profile `RuntimeDefault` | `LabValidate.bash` |
| H | All capabilities dropped (`capabilities.drop` contains `ALL`) | `LabValidate.bash` |
| I | Proof that a Pod violating the profile is rejected by the API server | `LabValidate.bash` (live admission test) |

## What the restricted profile actually demands

| Field | Requirement | Where it may be set |
|---|---|---|
| `runAsNonRoot` | `true` | pod level or container level |
| `runAsUser` | not 0 | pod level or container level |
| `allowPrivilegeEscalation` | `false` | container level only |
| `seccompProfile.type` | `RuntimeDefault` or `Localhost` | pod level or container level |
| `capabilities.drop` | must contain `ALL` | container level only |
| `capabilities.add` | may only add `NET_BIND_SERVICE` | container level only |

## Gotchas

- **Pod Security Admission is enforced by the API server, not by a
  controller.** There is nothing to install, no webhook to deploy and no
  CustomResourceDefinition to create. The namespace labels are the whole
  mechanism. A common wrong turn is looking for a `PodSecurityPolicy` object
  or an admission controller deployment; on a modern cluster neither exists.

- **The label is `pod-security.kubernetes.io/enforce` on the namespace.** The
  value is the profile name: `privileged`, `baseline` or `restricted`. Setting
  it to `restricted` on a *Pod* does nothing; it is a namespace label.

- **A namespace can carry three levels at once.** `enforce` rejects the
  request outright, `warn` lets the request through but returns a warning,
  and `audit` records a warning in the audit log without changing the
  response. Only `enforce` actually blocks the Pod, which is why the grader
  creates a violating Pod and checks that the create fails.

- **`enforce-version` is optional.** If you set it, it has to name a version
  the API server understands — `v1.23`, `v1.25`, `v1.29`, `latest` and so on.
  If you leave it out, the API server uses its own default. The task does not
  require it.

- **Changing the labels does not evict anything.** The restriction is applied
  at admission time, so a Pod that is already running in the namespace keeps
  running when you add the `enforce` label. Only Pods created *after* the
  label are checked. If the candidate wants to prove enforcement, they have to
  try to create a new Pod.

- **The Pod-level fields cover the containers.** `runAsNonRoot`, `runAsUser`
  and `seccompProfile` set on the Pod apply to every container, which is why
  a compliant Pod can carry them in `spec.securityContext`. The container-only
  fields — `allowPrivilegeEscalation` and `capabilities` — have to be on each
  container.

- **Setting the label and creating the Pod in the wrong order fails.** If the
  candidate labels the namespace first and then creates a Pod that does not
  satisfy the profile, the API server rejects the Pod and it never exists.

## Environment requirements

- A cluster with at least one node and a working kube-apiserver.
- Pod Security Admission enabled (the default; it is a beta feature that is
  on by default from Kubernetes 1.23 onwards).
- Registry access for `busybox:stable`.
- No extra components: no OPA/Gatekeeper, no Kyverno, no PodSecurityPolicy.
