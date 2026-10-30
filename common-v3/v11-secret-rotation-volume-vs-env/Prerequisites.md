# v11 — Which one sees the new value?: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `rot` | `LabSetUp.bash` | The Secret and the Deployment live here, and the task names the namespace. Recreated on every run, so the pre-state is always the same. |
| 2 | Secret `app-secret`, key `TOKEN` | `LabSetUp.bash` | The thing being rotated. It starts with `old-value` so the setup can rotate it to `new-value` after the pod is already running. |
| 3 | Deployment `app`, 1 replica, `nginx:1.25`, labels `app=app` | `LabSetUp.bash` | The workload under investigation. It reads the same Secret twice, which is the whole point of the question. |
| 4 | The Secret read as the environment variable `TOKEN` (`secretKeyRef`) | `LabSetUp.bash` | One of the two readers. The kubelet resolves the reference and injects the value when the container starts. |
| 5 | The Secret mounted as a volume at `/etc/secret` | `LabSetUp.bash` | The other reader. The kubelet projects the Secret into the container's filesystem and keeps it up to date. |
| 6 | The pod already running **before** the rotation | `LabSetUp.bash` waits for `readyReplicas == 1` | This is what makes the pre-state interesting. The container captured `old-value` at start-up, so it is still holding it after the Secret changes. The setup warns if the pod never became ready. |
| 7 | The Secret already rotated to `new-value` | `LabSetUp.bash` patches the Secret after the pod is ready | The candidate inherits the rotation, not the act of rotating. The setup warns if the environment variable is not still `old-value` afterwards, because then the stale-value half of the puzzle is missing. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | The Secret `app-secret` still holds `TOKEN=new-value` | `LabValidate.bash` |
| B | Inside the pod, `/etc/secret/TOKEN` holds `new-value` — checked with a retry, up to three minutes, because the kubelet refreshes the projection on its own schedule | `LabValidate.bash` |
| C | The Deployment's `TOKEN` env var still comes from a `secretKeyRef` on `app-secret` — not a hard-coded literal | `LabValidate.bash` |
| D | The container's `TOKEN` environment variable holds `old-value` or `new-value` — either is acceptable, depending on whether the pod has been restarted | `LabValidate.bash` |
| E | The Secret is still mounted at `/etc/secret` | `LabValidate.bash` |
| F | The pod is Running with 1 ready container | `LabValidate.bash` |

## Gotchas

- **This is the lesson the question is built around.** An environment variable is
  read **once**, when the container starts. The kubelet resolves the
  `secretKeyRef` at start-up and the value is baked into the container's
  environment for its whole life. A rotated Secret does not change it, and the
  only way to pick up the new value is a restart of the pod.

- **A Secret mounted as a volume is a projection, not a copy.** The kubelet
  watches the Secret and rewrites the files in the mounted directory in place.
  The update arrives on the kubelet's own schedule — commonly within a minute,
  and allowed to take up to about two — so a file that still shows the old
  value immediately after a rotation proves nothing. Wait before you conclude
  anything.

- **`subPath` mounts are never refreshed.** This is the classic trap. A
  `volumeMount` with `subPath: TOKEN` binds that one file into the container,
  and the kubelet does not update it when the Secret changes. The same Secret
  mounted at `/etc/secret` without `subPath` is a projection and does refresh.
  If a candidate "fixes" the mounted file by switching to `subPath`, the
  rotation silently stops working.

- **Which one you want depends on the application.** If the program reads its
  configuration once at start-up, an environment variable is the right choice
  and you accept that a rotation needs a restart. If the program re-reads its
  configuration on every request, the mounted file is the right choice and the
  rotation takes effect with no restart at all. The question is not "which is
  correct" — it is "which one updates by itself".

- **The tempting wrong answer is to hard-code the value.** Replacing the
  `secretKeyRef` with `value: new-value` makes the environment variable read
  correctly and permanently breaks the next rotation. The validator checks that
  the reference is still there.

- **The tempting wrong answer is to edit the Secret by hand.** The Secret has
  already been rotated — that is the pre-state, not the task. The task is to
  work out what the pod sees, and to make the pod serve the new value.

## Environment requirements

- A working cluster with at least one node, and registry access for
  `nginx:1.25`.
- A kubelet that supports projected Secret volumes — every mainstream CNI and
  every current kubelet does. The `subPath` behaviour described above is
  universal, not implementation-specific.
- No special components. This is ordinary kubelet behaviour.
- The validator waits up to three minutes for the mounted file to catch up.
  That is deliberate: a candidate who checks the file once, immediately, will
  see the old value and draw the wrong conclusion.
