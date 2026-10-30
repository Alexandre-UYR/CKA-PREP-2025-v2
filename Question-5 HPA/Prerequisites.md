# Q5 — HPA: prerequisite inventory

The exam hands you a cluster and a task. This file lists everything that was
already in the cluster when you opened the task, and why each piece is there.

## Prerequisite inventory

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `autoscale` | `LabSetUp.bash` | The task says "in the autoscale namespace". The namespace has to exist before an HPA can live in it. |
| 2 | `metrics-server` Deployment in `kube-system`, patched with `--kubelet-insecure-tls` | `LabSetUp.bash` | An HPA with a CPU metric needs a metrics source. metrics-server is that source; without it the HPA sits at `<unknown>` and never scales. The `--kubelet-insecure-tls` flag is needed because the kubelet serves its metrics with a self-signed certificate. |
| 3 | Deployment `apache-deployment` in `autoscale` (image `httpd`, 1 replica, `requests.cpu: 100m`, `limits.cpu: 200m`) | `LabSetUp.bash` | This is the workload the HPA targets. The task names it explicitly ("target the existing deployment called apache-deployment"), so it is pre-state, not yours to create. |
| 4 | CPU **request** of `100m` on the container | `LabSetUp.bash` | A CPU utilization metric is a percentage *of the request*. Without a request there is no denominator, so `averageUtilization: 50` would be meaningless and the HPA could not compute a target. |
| 5 | Service `apache-deployment` in `autoscale` (port 80) | `LabSetUp.bash` | A normal Service for the workload. The task does not mention it, but a working Service is what makes the scaled-up pods reachable, and it is what the cluster looks like in a real environment. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| 1 | HPA `apache-server` in namespace `autoscale` | `kubectl get hpa apache-server -n autoscale` succeeds |
| 2 | `spec.scaleTargetRef` = `{name: apache-deployment, kind: Deployment, apiVersion: apps/v1}` | `spec.scaleTargetRef.name` / `.kind` / `.apiVersion` |
| 3 | `spec.minReplicas: 1` and `spec.maxReplicas: 4` | `spec.minReplicas`, `spec.maxReplicas` |
| 4 | `spec.metrics[0]`: `type: Resource`, `resource.name: cpu`, `resource.target.type: Utilization`, `resource.target.averageUtilization: 50` | the four `spec.metrics[0].*` paths |
| 5 | `spec.behavior.scaleDown.stabilizationWindowSeconds: 30` | `spec.behavior.scaleDown.stabilizationWindowSeconds` |

## Gotchas

- **Check the spec, not the replica count.** `kubectl get hpa` shows a
  `TARGETS` column and a live replica count. If metrics-server is not working,
  that column reads `<unknown>/50%` and the HPA never scales, even though the
  object is perfectly correct. The grader therefore reads the HPA spec out of
  the API, and never looks at how many pods exist.
- **`averageUtilization` is a percentage of the request, not of the limit.**
  The deployment asks for `100m` CPU, so "50%" means "scale when the pod is
  using about 50m".
- **`minReplicas` defaults to 1.** If you leave it out, the stored object still
  says `1` and the check passes — but write it explicitly, because the exam
  asks for it.
- **The stabilization window belongs under `scaleDown`,** not `scaleUp`, and it
  is a sibling of `policies`, not a child of it:
  `spec.behavior.scaleDown.stabilizationWindowSeconds: 30`.
- **`apiVersion: autoscaling/v2` is what you want** for a CPU utilization
  metric with a behavior block. `autoscaling/v2beta1` and `v1` are older; `v1`
  cannot express `behavior` at all.

## Environment requirements

- **metrics-server must be installed and healthy.** It is installed by
  `LabSetUp.bash`, but a busy or offline cluster may not pull the image, in
  which case the HPA will report `<unknown>` for its current metric. That is an
  environment problem, not an answer problem — do not "fix" it by changing the
  HPA.
- **The kubelet must be reachable with insecure TLS**, which is why the setup
  patches metrics-server with `--kubelet-insecure-tls`.
- **The deployment's pods must be Running** for the HPA to compute a metric
  against them.
- **Nothing here needs node-level access or a free nodePort.** The question is
  entirely API-server-side.
