# c20 — Run a Pod with restricted privileges: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `secure`, with no Pod Security Admission labels on it | `LabSetUp.bash` | The task places the Pod in this namespace. It has to exist before the Pod can be created in it, and it has to be a plain namespace, because the candidate is writing the securityContext by hand here — nothing is going to enforce it for them. |
| 2 | A cluster with a working scheduler and at least one node that can run `busybox:stable` | the cluster itself | The Pod has to start, not just exist. The image the candidate picks has to be able to run as uid 1000, so a plain busybox-style image is the safe choice and an image that needs to bind a privileged port is not. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | A Pod named `restricted` in namespace `secure` | `LabValidate.bash` |
| B | The Pod is actually Running and Ready | `LabValidate.bash` |
| C | Pod-level `securityContext.runAsUser: 1000` | `LabValidate.bash` |
| D | Pod-level `securityContext.runAsNonRoot: true` | `LabValidate.bash` |
| E | Container-level `securityContext.allowPrivilegeEscalation: false` | `LabValidate.bash` |
| F | Container-level `securityContext.capabilities.drop: ["ALL"]` | `LabValidate.bash` |
| G | No capability added back (`capabilities.add` empty or absent) | `LabValidate.bash` |
| H | Seccomp profile `RuntimeDefault`, on the pod or on the container | `LabValidate.bash` |

## Why this pre-state is deliberately thin

Most of these questions reproduce a *broken* environment, because that is what
the exam tests. This one does not: the task is to **create** a Pod, so there is
nothing to break. Only the namespace exists.

The difficulty moves from "diagnose" to "get the shape of the object exactly
right". In this case the shape is the securityContext, and the shape has two
levels that are easy to confuse:

- The **Pod** securityContext (`spec.securityContext`) carries `runAsUser`,
  `runAsNonRoot`, `runAsGroup`, `fsGroup` and `seccompProfile`.
- The **Container** securityContext (`spec.containers[].securityContext`)
  carries `allowPrivilegeEscalation`, `capabilities`, `privileged`,
  `readOnlyRootFilesystem`, `runAsUser` and `seccompProfile`.

## Gotchas

- **`runAsNonRoot: true` and `runAsUser` have to agree.** `runAsNonRoot: true`
  tells the kubelet to refuse to start the container if it would run as uid 0.
  If the image runs as root and you have not pinned a non-zero `runAsUser`,
  the kubelet refuses the container with `container has runAsNonRoot and image
  has non-numeric user` (when the image's USER is a name) or `container has
  runAsNonRoot and image will run as root` (when it is numeric 0). Setting
  `runAsUser: 1000` alongside `runAsNonRoot: true` resolves it, because the
  kubelet can then see the uid is not 0 without inspecting the image.

- **`drop: ["ALL"]` removes every capability; adding one back is the opposite
  of the task.** The task says *do not add any capability back*, and the grader
  checks it. `capabilities.drop` and `capabilities.add` are separate lists —
  a Pod with `drop: ["ALL"]` and `add: ["NET_ADMIN"]` is not more
  privileged, but it is also not what was asked for.

- **`allowPrivilegeEscalation: false` belongs on the container.** There is no
  `allowPrivilegeEscalation` field in a Pod's `spec.securityContext`; it is a
  container field. Putting it in the wrong place means the API server accepts
  the manifest and silently ignores the field, so the Pod runs with
  privilege escalation still permitted.

- **The seccomp profile goes on the pod** (or, if you want it per container,
  on the container's `securityContext`). `RuntimeDefault` is the profile that
  uses the container runtime's default seccomp setup; the other legal value is
  `Localhost`, which points at a profile file on the node.

- **The image has to survive running as uid 1000.** A container image that
  expects to write to a root-owned path, or to bind a port below 1024, will
  fail at runtime under a non-root uid even though the securityContext is
  perfect. `busybox` with a `sleep` command has no such problem.

- **Setting a securityContext is not the same as enforcing one.** A
  securityContext is a request to the kubelet about one Pod. Nothing in the
  cluster rejects a Pod for violating it. That is the subject of c21.

## Environment requirements

- A cluster with at least one node and a working scheduler.
- Registry access for `busybox:stable` (or whatever image the candidate
  chooses).
- A kubelet that honours `runAsNonRoot`, `allowPrivilegeEscalation` and
  seccomp profiles — any current Kubernetes release does.
- No admission controller, no PSA labels and no special CNI: this is a plain
  Pod with no networking requirements.
