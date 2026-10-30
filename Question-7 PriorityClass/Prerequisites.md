# Q7 — PriorityClass: prerequisite inventory

The exam hands you a cluster and a task. This file lists everything that was
already in the cluster when you opened the task, and why each piece is there.

## Prerequisite inventory

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `priority` | `LabSetUp.bash` | The deployment named in the task lives here, and the patched Deployment has to go back into the same namespace. |
| 2 | PriorityClass `user-critical`, `value: 1000`, `globalDefault: false` | `LabSetUp.bash` | The task says "the cluster already has at least one user defined Priority Class" and asks for a value "exactly one less than the highest existing user-defined priority class". There has to be a user-defined class to compute "one less than the highest" from. 1000 is a plausible high user value. |
| 3 | Deployment `busybox-logger` in `priority` (1 replica, no `priorityClassName`) | `LabSetUp.bash` | The task says to *patch* this deployment to use the new class. It must already exist, and it must start with no priority class so the patch is visible. |
| 4 | The deployment's UID, captured to `/tmp/cka-lab/q7.deploy.uid` | `LabSetUp.bash` (last line) | The task asks for a patch, not a replacement. The only way to prove the object was patched rather than deleted and recreated is to compare its UID against the one recorded before the candidate started. |
| 5 | The two system PriorityClasses `system-cluster-critical` (2000000000) and `system-node-critical` (2000000001) | The cluster itself | They are part of the "highest existing priority class" wording, and they are the trap: they are not user-defined, so they must be excluded from the "one less than" computation. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| 1 | PriorityClass `high-priority` exists | `kubectl get priorityclass high-priority` succeeds |
| 2 | Its `value` is exactly one less than the highest user-defined value (here 999) | the highest value among PriorityClasses whose name does not start with `system-`, minus one, compared with `.value` |
| 3 | Deployment `busybox-logger` was **patched**, not recreated | its `metadata.uid` is unchanged from the one captured at setup time |
| 4 | The pod template uses the new class | `spec.template.spec.priorityClassName == high-priority` |

## Gotchas

- **"One less than the highest existing user-defined priority class" — not the
  highest PriorityClass in the cluster.** `system-cluster-critical` is
  2000000000 and `system-node-critical` is 2000000001. If you subtract one from
  those you get a value in the billions, and every ordinary workload is
  preempted by the system. Filter the system classes out: the highest
  *user-defined* value here is 1000, so the answer is 999.
- **The value must be computed, not guessed.** The task is phrased
  relative to whatever is in the cluster, so a hard-coded `--value=999` only
  works on this particular pre-state. Read the classes and subtract one.
- **`priorityClassName` lives on the POD TEMPLATE,** not on the Deployment's
  top-level spec:
  `spec.template.spec.priorityClassName`, inside `spec.template.spec`, which
  is inside `spec`.
- **Patch, do not recreate.** `kubectl delete` + `kubectl create` of the
  deployment would satisfy the "uses high-priority" check but breaks the
  constraint in the task. Use `kubectl patch deployment ...` with the pod
  template path, which is what the task asks for.
- **Patching the pod template rolls the deployment.** The pods are recreated
  with the new priority class. That is expected; the Deployment object itself
  keeps its UID.
- **`globalDefault` is not part of the new class.** Only `user-critical` sets
  it, and the task does not ask for it on `high-priority`.

## Environment requirements

- **No node-level access is needed.** Everything is API-server-side, apart from
  writing the UID file to `/tmp/cka-lab/`, which the setup does for you.
- **`/tmp/cka-lab/` must be writable** for the setup to record the deployment
  UID. The setup creates the directory if it does not exist.
- **The priority admission controller must be running** (it is, by default, as
  part of kube-scheduler) for the priority class to have any effect. The
  checks here are on the objects, not on the scheduler's behaviour.
