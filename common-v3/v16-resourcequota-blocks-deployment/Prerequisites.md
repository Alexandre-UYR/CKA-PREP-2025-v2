# v16 — The API server that says no: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `quota` | `LabSetUp.bash` | The quota, the limit range and the workload all live here, and the task names the namespace. |
| 2 | ResourceQuota `compute-quota` with hard `requests.cpu` 2, `requests.memory` 4Gi, `limits.cpu` 2, `limits.memory` 4Gi | `LabSetUp.bash` | The cause of the failure. A quota on those four fields means every Pod in the namespace has to declare all four; a Pod that does not is refused. The hard limits are set so that a sensible answer fits inside them. |
| 3 | The quota is created **before** the workload attempt | `LabSetUp.bash` | The refusal only happens if the quota is already there when the Pod is admitted. |
| 4 | A Deployment `app` (nginx, 1 replica) with no resources at all | `LabSetUp.bash` | The attempt. The setup creates it, the API server refuses to let it create a Pod, and the refusal is captured. The attempt is then removed again so the candidate writes the manifest that gets accepted. |
| 5 | The captured refusal, reported by the setup | `LabSetUp.bash` waits for it | The pre-state has to BE the refusal. The setup polls the ReplicaSet's `ReplicaFailure` condition until the error appears, and warns if it never does. |
| 6 | LimitRange `defaults` supplying `defaultRequest.memory` 512Mi and `default.memory` 1Gi | `LabSetUp.bash`, after the attempt | The second route. It covers **memory only**, on purpose: if it covered CPU as well, a manifest with no resources at all would be admitted and the quota would never be felt. With it as it is, the candidate can declare the CPU values and let the namespace supply the memory ones. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | The ResourceQuota `compute-quota` still exists in namespace `quota`, and still requires all four resources | `LabValidate.bash` |
| B | The quota's hard limits were not raised to make room | `LabValidate.bash` |
| C | A Deployment `app` exists in namespace `quota` — the API server accepted it | `LabValidate.bash` |
| D | Its container declares `requests.cpu`, `requests.memory`, `limits.cpu` and `limits.memory`, all non-empty — either in the Deployment's pod template, or in the running Pod when the LimitRange supplied them | `LabValidate.bash` |
| E | The sum of the requests fits inside the quota's hard limits | `LabValidate.bash` |
| F | The Deployment has 1 ready replica, the Pod is `Running` and has 1 ready container | `LabValidate.bash` |

## Gotchas

- **A ResourceQuota is enforced at ADMISSION time, by the API server, not by
  a controller.** The Pod is refused on the way in, so nothing is created and
  there is no object to look at afterwards — only the error, which names the
  quota and the fields that are missing. This is the whole shape of the
  question: the absence of an object is the evidence.

- **The Deployment object itself is admitted; it is the Pod that is refused.**
  Quota is checked when a Pod is created, so `kubectl apply` of a
  resource-less Deployment succeeds and the failure shows up a moment later
  as `FailedCreate` on the ReplicaSet and as an event. If a candidate
  concludes "the API server accepted my Deployment, so the quota does not
  apply", they have missed where quota is actually enforced. Read the
  ReplicaSet's condition and the events, not just the Deployment.

- **The error message is the diagnostic.** "must specify limits.cpu,
  limits.memory, requests.cpu, requests.memory" tells you exactly which four
  fields the manifest is missing. It is worth reading rather than guessing.

- **Both routes are legitimate, and the validator accepts both.** Declare all
  four fields on the container yourself, or declare the CPU values and let
  the LimitRange supply the memory ones. The LimitRange merges its defaults
  into a container **per resource** at Pod admission, so a container that
  already sets `requests.cpu` still gets `requests.memory` and
  `limits.memory` filled in — and the quota then sees the defaulted values.

- **The defaults land on the Pod, not on the Deployment.** The LimitRanger
  admission plugin only sees Pods, so the Deployment's pod template keeps
  whatever it was written with; the defaults exist only in the created Pod.
  That is why the validator checks the Pod's resources as well as the
  Deployment's.

- **Do not delete the quota, and do not raise its limits.** The quota is
  pre-state, and it is what makes the exercise an exercise. The validator
  checks that it is still there, still requires the four resources, and still
  has the same hard limits.

- **Requests must not exceed limits.** A container with `requests.cpu` larger
  than its `limits.cpu` is rejected by the API server on its own account,
  with a different error that has nothing to do with the quota.

- **The hard limits are deliberately generous.** Two CPUs and 4Gi of memory
  is enough for any sensible answer, so a candidate who writes
  `requests.cpu: 100m`, `requests.memory: 128Mi`, `limits.cpu: 500m`,
  `limits.memory: 512Mi` is admitted immediately.

## Environment requirements

- A cluster with at least one node and `kubectl` in the current context.
- Registry access for `nginx:1.25`.
- The `ResourceQuota` admission plugin enabled. It is part of the default
  enabled admission chain, along with `LimitRanger`, which is what applies
  the LimitRange defaults. The ordering matters: `LimitRanger` runs in the
  mutating phase, so its defaults are in place before `ResourceQuota` runs
  in the validating phase and checks them.
- No special components: this is plain namespace quota plumbing.
