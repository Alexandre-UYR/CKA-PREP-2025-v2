# c26 — Horizontal autoscaling: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `autoscale` | `LabSetUp.bash` | The task says "in the autoscale namespace". The namespace has to exist before the HPA can live in it. |
| 2 | Deployment `web` in `autoscale` — image `nginx`, 2 replicas, label `app=web` | `LabSetUp.bash` | This is the workload the HPA targets. The task names it explicitly ("targets the existing Deployment `web`"), so it is pre-state, not yours to create. |
| 3 | CPU **request** of `100m` on the container | `LabSetUp.bash` | A CPU utilisation metric is a percentage *of the request*. Without a request there is no denominator, so `averageUtilization: 60` would be meaningless and the HPA could not compute a target. |
| 4 | CPU **limit** of `200m` on the container | `LabSetUp.bash` | It makes the workload realistic and it is the trap in the wording: the target is a percentage of the request, not of the limit. The limit only caps the container. |
| 5 | The Deployment's UID, recorded in `/tmp/cka-lab/c26.uid` | `LabSetUp.bash` | The task says not to re-create the Deployment. A UID recorded before the task and compared after it is the only way to prove the object was edited rather than replaced. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | HPA `web-hpa` in namespace `autoscale` | `kubectl get hpa web-hpa -n autoscale` succeeds |
| B | `spec.scaleTargetRef.name` is `web` and `spec.scaleTargetRef.kind` is `Deployment` | the two `spec.scaleTargetRef.*` paths |
| C | `spec.minReplicas: 2` | `spec.minReplicas` |
| D | `spec.maxReplicas: 8` | `spec.maxReplicas` |
| E | `spec.metrics[0]`: `type: Resource`, `resource.name: cpu`, `resource.target.type: Utilization`, `resource.target.averageUtilization: 60` | the four `spec.metrics[0].*` paths |
| F | `spec.behavior.scaleDown.stabilizationWindowSeconds: 60` | `spec.behavior.scaleDown.stabilizationWindowSeconds` |
| G | The `web` Deployment still carries the UID it had at setup time | `metadata.uid` compared with `/tmp/cka-lab/c26.uid` |

## Gotchas

- **Check the spec, not the replica count.** `kubectl get hpa` shows a
  `TARGETS` column and a live replica count. If metrics-server is not
  working, that column reads `<unknown>/60%` and the HPA never scales, even
  though the object is perfectly correct. The grader therefore reads the HPA
  spec out of the API and never looks at how many pods exist. If you are
  working through this by hand and the HPA shows `<unknown>`, that is the
  environment, not your manifest.

- **`averageUtilization` is a percentage of the request, not of the limit.**
  The Deployment asks for `100m` CPU, so "60%" means "scale when the pod is
  using about 60m". The limit of `200m` is not the denominator. If the pod had
  **no CPU request at all**, there is no meaningful utilisation to scale on:
  the HPA cannot compute a percentage against nothing, and it reports
  `<unknown>` for the target even though your manifest is perfectly formed.

- **`minReplicas` defaults to 1.** If you leave it out, the stored object still
  says `1` and the check fails — write it explicitly, because the exam asks
  for it.

- **The stabilisation window belongs under `scaleDown`,** not `scaleUp`, and it
  is a sibling of `policies`, not a child of it:
  `spec.behavior.scaleDown.stabilizationWindowSeconds: 60`.

- **`autoscaling/v2` is what you want** for a CPU utilisation metric with a
  behaviour block. `autoscaling/v1` cannot express `behavior` at all, and it
  spells the metric differently (`targetCPUUtilizationPercentage` instead of a
  `metrics` list), so the same number lands in a different field.

- **`kubectl autoscale` cannot set the stabilisation window.** The shorthand
  `kubectl autoscale deployment web --min=2 --max=8 --cpu-percent=60` gets
  every other field right, but there is no flag for the behaviour block. For
  the full answer, write the manifest out.

- **Do not re-create the Deployment.** `kubectl delete deployment web` followed
  by an `apply` gives you a Deployment that looks identical, but it is a
  different object with a different UID — and the pods of the old one are
  gone while the new ones are still pulling. The grader compares the UID
  recorded at setup time.

## Environment requirements

- A cluster with at least one node and a working scheduler.
- Registry access for `nginx`, so the `web` Deployment can actually pull its
  image. The grader does not need the pods to be Ready — it reads the HPA
  spec — but a Deployment that never starts is not a realistic environment.
- **metrics-server is optional for this question.** An HPA with a CPU metric
  needs a metrics source to *act* on, and metrics-server is that source.
  Without it the HPA sits at `<unknown>` for its current metric and never
  scales, even though the HPA object is entirely correct. That is why the
  grader checks the spec and never the replica count. If metrics-server is
  installed and healthy, the HPA may well scale the Deployment up on its own;
  that is expected and it does not affect the score.
- Nothing here needs node-level access, a free nodePort or a privileged
  container. The question is entirely API-server-side.
