# x16 — Two rules that contradict each other: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `conflict` | `LabSetUp.bash` | Both objects and the Pod live here, and the task names the namespace. |
| 2 | LimitRange `defaults`, type `Container`, `default: {cpu: 2, memory: 4Gi}`, `defaultRequest: {cpu: 1, memory: 2Gi}` | `LabSetUp.bash` | The defaults. The LimitRanger admission plugin fills them into every container that does not state its own resources — and they are **larger than the quota allows**. |
| 3 | ResourceQuota `tight`, hard `limits.cpu: 1`, `limits.memory: 1Gi`, `requests.cpu: 500m`, `requests.memory: 512Mi` | `LabSetUp.bash` | The ceilings. The ResourceQuota admission plugin refuses anything that exceeds them. The task forbids changing it. |
| 4 | Both objects' specs recorded | `LabSetUp.bash`, into `/tmp/cka-lab/x16.before` | The task forbids changing either object, so the grader compares their live specs against this copy. |
| 5 | The conflict proved | `LabSetUp.bash` creates a Pod with no resources and expects it to be refused | The pre-state has to BE the broken state. The setup shows the refusal, and warns if the Pod was accepted. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | Pod `fits` in namespace `conflict`, Running, with its container ready | `LabValidate.bash` |
| B | Its requests and limits all stated | `LabValidate.bash` |
| C | Every request and every limit inside the quota's hard values, compared numerically | `LabValidate.bash` |
| D | The ResourceQuota `tight` and the LimitRange `defaults` unchanged | `LabValidate.bash` (against `/tmp/cka-lab/x16.before`) |
| E | The quota's `status.used` accounting for the Pod | `LabValidate.bash` |

## Gotchas

- **A ResourceQuota is enforced at admission time and a LimitRange is enforced
  at admission time too.** One sets DEFAULTS, the other sets CEILINGS, and
  when the defaults are larger than the ceiling nothing can be created at
  all. The two objects are not aware of each other; only the API server puts
  them together.

- **The LimitRanger plugin runs first.** It fills in the missing requests and
  limits of every container, and only then does the ResourceQuota plugin look
  at the result. So a Pod that asks for nothing is refused for asking for
  `limits.cpu=2, limits.memory=4Gi` — amounts nobody asked for. The error
  message names the quota and the four numbers, and the numbers are the
  LimitRange's, not the Pod's.

- **The API server's admission order is not obvious from the manifest.** The
  LimitRange has to exist *before* the Pod is created, and it does — the
  namespace starts with both objects in place.

- **Stating the limits only is enough, and is a trap.** When a container has
  limits but no requests, the LimitRanger sets the requests to the limits.
  So `limits: {cpu: 500m, memory: 512Mi}` also gives requests of 500m and
  512Mi, which fits. It works — but it is one number away from being
  refused, and the Pod is then relying on the namespace to fill in half of
  its resources. State all four fields.

- **Comparing the numbers means comparing quantities, not strings.** `1` and
  `1000m` are the same amount of CPU; `1Gi` and `1024Mi` are the same amount
  of memory. A quota of `requests.cpu: 500m` is satisfied by a request of
  `0.5`.

- **The quota is the ceiling, the LimitRange is the floor — here the ceiling
  is lower.** The limits that are acceptable are therefore smaller than the
  namespace's defaults, not larger. The Pod has to fit inside the smaller of
  the two, which is the quota, because the quota is what refuses it.

- **`status.used` is updated by a controller, not by the API server.** After
  the Pod is admitted the quota's usage is a moment behind. The grader waits
  for it.

## Environment requirements

- A cluster with at least one node, and registry access for `busybox:1.28`.
- The ResourceQuota and LimitRange admission plugins enabled — they are on
  by default in every standard distribution.
- No special components.
