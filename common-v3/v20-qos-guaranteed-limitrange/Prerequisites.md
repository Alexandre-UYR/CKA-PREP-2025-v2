# v20 — Guaranteed, not Burstable: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `qos` | `LabSetUp.bash` | The LimitRange, the Deployment and its pod live here, and the task names the namespace. |
| 2 | LimitRange `defaults` with `default` (cpu 100m, memory 128Mi) and `defaultRequest` (cpu 50m, memory 64Mi) | `LabSetUp.bash` | This is the trap. The LimitRanger admission plugin fills in the resources a container leaves unset: `default` for missing **limits**, `defaultRequest` for missing **requests**. The pod therefore ends up with requests, and they are smaller than its limits. |
| 3 | The LimitRange exists **before** the pod is created | `LabSetUp.bash` applies the LimitRange first | The defaults are applied by the admission plugin at pod creation time, not by the Deployment controller. Reverse the order and the pod comes up with no requests at all. |
| 4 | Deployment `mixed`, 1 replica, labels `app=mixed`, image `busybox:1.36` | `LabSetUp.bash` | The workload to be fixed in place. It exists so the candidate edits it rather than building something new. |
| 5 | One main container `app` that sets **only** `limits` (cpu 200m, memory 256Mi) and **no** requests | `LabSetUp.bash` | Half of the problem. The container looks like it has everything it needs; the requests it ends up with come from `defaultRequest` and do not match the limits. |
| 6 | One init container `init` that sets **nothing** at all | `LabSetUp.bash` | The other half. The init container ends up with `default` for its limits and `defaultRequest` for its requests — again unequal. It also matters because **init containers count towards the QoS class**, which is the detail the whole question turns on. |
| 7 | The pod is Running and reports `Burstable` | `LabSetUp.bash` waits for it | The pre-state has to actually BE the broken state. The setup polls for `status.qosClass == Burstable` and warns if it has not appeared. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | The Deployment `mixed` still exists in namespace `qos`, with one main container and one init container | `LabValidate.bash` |
| B | Every main container sets a CPU request equal to its CPU limit — compared numerically, so `200m` and `0.2` are the same value | `LabValidate.bash` |
| C | Every main container sets a memory request equal to its memory limit | `LabValidate.bash` |
| D | Every init container sets a CPU request equal to its CPU limit | `LabValidate.bash` |
| E | Every init container sets a memory request equal to its memory limit | `LabValidate.bash` |
| F | The init container's memory limit does not exceed the main container's memory limit (and the same for CPU) | `LabValidate.bash` |
| G | The pod is Running, runs exactly one container, and that container is ready | `LabValidate.bash` |
| H | The pod's `.status.qosClass` is `Guaranteed` | `LabValidate.bash` |

## Gotchas

- **The QoS class is computed by the kubelet from the pod's resource spec**, and the rules are:
  - **Guaranteed** — every container (init containers included) sets CPU and memory requests equal to its limits.
  - **Burstable** — at least one container has a request, but the conditions for Guaranteed are not met.
  - **BestEffort** — no container has any requests or limits.

- **Init containers count.** A pod is not Guaranteed if every *main* container is
  Guaranteed but the init container is not. Fixing only the `app` container
  leaves the pod Burstable, and the class on the pod says so.

- **The LimitRange is what makes this question interesting.** It silently fills
  in the missing requests with its `defaultRequest` values, so the pod LOOKS
  like it has requests while they do not match the limits. That is why simply
  checking that requests exist is not enough, and why the class has to be read
  from the pod's own status rather than inferred from the manifest.

- **`kubectl get deploy -o yaml` shows the truth about the template, not about
  the pod.** The LimitRanger plugin only touches Pods, so the Deployment's
  template still shows `limits` with no `requests` at all. The filled-in
  requests appear in `kubectl get pod -o yaml`. Reading only the Deployment
  makes it look as though the pod has no requests, which is not what the
  kubelet sees.

- **The right fix is on the Deployment, not on the pod.** A hand-edited pod
  keeps the right QoS class until the Deployment replaces it. The validator
  checks the Deployment's template as well as the live pod, so a pod-only edit
  does not pass.

- **Tightening `defaultRequest` to match `default` is not the answer.** It
  would make the pod Guaranteed, but the task asks for the containers to set
  their own requests equal to their limits, and the init container's own
  requests still have to be there.

- **Watch the rollout.** The validator waits for the new pod to come up and
  report `Guaranteed` before it grades, so a slow rollout is not mistaken for
  a wrong answer.

## Environment requirements

- A cluster with at least one schedulable node.
- Registry access for `busybox:1.36`.
- The LimitRanger admission plugin enabled — it is on by default in a standard
  cluster, and the question does not work without it.
- No special components: this is plain kubelet and API server behaviour.
