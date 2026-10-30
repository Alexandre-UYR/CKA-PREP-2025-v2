# v9 — Protect the workload from voluntary disruption: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `pdb` | `LabSetUp.bash` | The task names the namespace, and both the Deployment and the budget live there. |
| 2 | Deployment `api`, 3 replicas, labels `app=api` | `LabSetUp.bash` | The workload the budget has to protect. It is healthy on purpose: a budget is only meaningful against a healthy workload, and the candidate can see CURRENT HEALTHY fill up. |
| 3 | Three ready replicas | `LabSetUp.bash` waits for `readyReplicas == 3` and warns if it does not happen | "At most one of its pods" needs more than one pod to be a question. With three replicas, `maxUnavailable: 1` and `minAvailable: 2` mean the same thing, and ALLOWED DISRUPTIONS reads 1. |
| 4 | No PodDisruptionBudget in the namespace | `LabSetUp.bash` creates none | The gap the candidate has to close. `kubectl -n pdb get pdb` comes back empty, so the workload is one drain away from losing everything. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | A PodDisruptionBudget `api-pdb` in namespace `pdb` | `LabValidate.bash` |
| B | A selector of its own that matches the api pods — an empty selector is not accepted | `LabValidate.bash` |
| C | The budget really selects the api pods: CURRENT HEALTHY equals the number of api replicas, and EXPECTED PODS does too | `LabValidate.bash` |
| D | `maxUnavailable: 1` or `minAvailable: 2` — one of the two, not both | `LabValidate.bash` |
| E | `ALLOWED DISRUPTIONS` is 1 — the live proof that the budget took effect | `LabValidate.bash` |

## Gotchas

- **A PodDisruptionBudget constrains VOLUNTARY disruption.** A node drain, an
  autoscaler removing a pod, a pod evicted through the eviction API. It does
  **not** protect against a node that fails, a container that is killed, or
  anything else that is not a deliberate eviction. A candidate who believes a
  PDB keeps the pods alive through a node failure has misunderstood what the
  object does.

- **The selector must match the pods.** This is the part people get wrong, and
  the two ways of getting it wrong fail in opposite directions:
  - `selector: {}` — an empty selector matches **every pod in the namespace**.
    It is not "no selector", it is "all pods".
  - `selector: {matchLabels: {tier: api}}` — a label the pods do not carry
    matches **no pods at all**, and the budget then silently protects nothing
    while looking perfectly well-formed in the YAML.

- **ALLOWED DISRUPTIONS is the check that tells you which of those you got.** A
  budget whose selector matches nothing reports 0 disruptions allowed and 0
  healthy pods; a budget with an empty selector reports the whole namespace.
  Read the column, not the manifest.

- **`maxUnavailable` and `minAvailable` are two ways of saying the same thing
  here.** With three replicas, "at most one unavailable" and "at least two
  available" are the same budget — and ALLOWED DISRUPTIONS reads 1 either way.
  You may set only one of them: the API server rejects a budget that sets both.

- **`minAvailable` is a floor and `maxUnavailable` is a ceiling.** They are
  not interchangeable when the pod count is unknown — `minAvailable: 2` on a
  one-replica Deployment allows no disruption at all, while
  `maxUnavailable: 1` allows the only pod to go.

- **The eviction API is what enforces the budget, and it waits.** A drain does
  not fail when the budget is exceeded; it *blocks* and retries. A budget that
  is too tight (say `minAvailable: 3` on three replicas) makes the drain hang
  forever, which is a different failure from the one this question is about.

## Environment requirements

- A cluster with at least one node that can run three small nginx pods.
- Registry access for `nginx:1.25`.
- No special components. The disruption controller and the eviction API are
  part of the API server and the controller manager.
