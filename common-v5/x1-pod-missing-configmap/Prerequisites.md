# x1 — The pod that will not start: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `diag` | `LabSetUp.bash` | The Pod lives here and the task names the namespace. |
| 2 | Pod `web`, container `busybox:1.36` running `sleep 3600`, with `envFrom.configMapRef.name: app-config` | `LabSetUp.bash` | The workload under investigation. It sources its whole environment from a ConfigMap that does not exist, so the kubelet cannot build the container and the Pod never starts. |
| 3 | **No** ConfigMap named `app-config` anywhere | the setup's absence of it | This is the failure. The API server accepts the Pod — the reference is only resolved when the kubelet builds the container — so the Pod object exists and looks fine. |
| 4 | A decoy ConfigMap `other-config` with `MODE=prod` | `LabSetUp.bash` | So the namespace is not obviously empty, and the candidate has to read the event rather than assume the ConfigMap was never created. Copying the decoy's contents under the right name is a legitimate fix. |
| 5 | The Pod's UID recorded | `LabSetUp.bash`, into `/tmp/cka-lab/x1.pod.uid` | The task forbids re-creating the Pod. The grader compares the UID at validate time with the one recorded here. |
| 6 | The Pod to have actually failed | `LabSetUp.bash` polls for the waiting reason | The pre-state has to BE the broken state. The setup waits for `CreateContainerConfigError` and warns if it never appeared. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | ConfigMap `app-config` in namespace `diag`, with `MODE=prod` | `LabValidate.bash` |
| B | The Pod running, with its container ready | `LabValidate.bash` |
| C | `MODE` actually set to `prod` inside the Pod | `LabValidate.bash` (live exec) |
| D | The Pod never re-created — its UID unchanged | `LabValidate.bash` |
| E | The container never crashed its way in — restartCount 0, and no `CreateContainerConfigError` in its last termination | `LabValidate.bash` |

## Gotchas

- **The Pod's status says "waiting", not why.** `kubectl get pod` shows
  `ContainerCreating`. The actual reason — that the referenced ConfigMap does not
  exist — is in the Pod's **events**, which is why `kubectl describe pod` and
  `kubectl get events` are the tools for this. The task points at this.

- **The API server accepts the Pod.** Nothing validates that a `configMapRef`
  names something that exists. The reference is only resolved at container
  start-up, on the node, by the kubelet. So `kubectl apply` succeeds and the
  problem appears afterwards.

- **`envFrom` takes a whole ConfigMap; `env` takes one key.** `envFrom` imports
  every key of the ConfigMap as an environment variable, so the variable the
  Pod ends up with is named after the KEY, not after anything the Pod asks for.
  The Pod here expects a variable called `MODE`, which means the ConfigMap must
  have a key called `MODE`.

- **The Pod's spec is immutable in this field.** `envFrom` cannot be changed on
  a running Pod, so "edit the Pod to point somewhere else" is not available —
  the environment has to be fixed around it. The UID check enforces that the
  candidate did not take the delete-and-recreate route either.

- **Deleting the Pod would work, and is still wrong.** It would produce a
  Running Pod with the right variable. The task forbids it, and the grader
  catches it by UID.

- **A ConfigMap with the right name but the wrong key does not help.** The
  variable would be missing even though the Pod starts. The live
  `printenv MODE` check is what catches that.

## Environment requirements

- A cluster with at least one node, and registry access for `busybox:1.36`.
- No special components. This is plain Pod and ConfigMap behaviour.
