# x14 — Make it work harder, then watch it: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `autoscale` | `LabSetUp.bash` | The Deployment, the Service, the HPA and the load generator all live here, and the task names the namespace. |
| 2 | Deployment `hpa-example` — 1 replica, `registry.k8s.io/hpa-example`, labels `app=hpa-example` | `LabSetUp.bash` | The workload the HPA targets, and the thing that has to scale. The image is the Apache/PHP app from the upstream HorizontalPodAutoscaler walkthrough; it serves HTTP on port 80. |
| 3 | The container requests `200m` of CPU and is limited to `500m` | `LabSetUp.bash` | The autoscaler has to have a **request** to work from. 50% of 200m is 100m of CPU per pod, so the pods have to average more than that before the HPA adds one. |
| 4 | Service `hpa-example` — ClusterIP, port 80 -> targetPort 80, selector `app=hpa-example` | `LabSetUp.bash` | The load generator needs something to talk to. It selects the pods, so it keeps working as the Deployment scales. |
| 5 | **No** metrics server anywhere in the cluster | the setup's absence of it | The failure. The autoscaler reads the `metrics.k8s.io` API, and nothing serves it, so no HPA could ever act. |
| 6 | The setup removes any metrics-server it finds | `LabSetUp.bash` | So the starting state is the same on every run, and so the "install a metrics server" step is real work. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | A metrics-server Deployment in `kube-system` | `LabValidate.bash` |
| B | The metrics API (`metrics.k8s.io/v1beta1`) answering | `LabValidate.bash` (gates the scale-up check) |
| C | HorizontalPodAutoscaler `hpa` in namespace `autoscale`, targeting the Deployment `hpa-example`, 1–10 pods, 50% of the CPU request | `LabValidate.bash` |
| D | A load generator Pod in `autoscale` running a loop that talks to the Service `hpa-example` | `LabValidate.bash` |
| E | The Deployment scaled above 1 replica | `LabValidate.bash` (SKIPped if the metrics API is not answering) |

## Gotchas

- **The CPU target is a percentage of the container's CPU REQUEST** — not of
  its limit, and not of the node. `averageUtilization: 50` against a request
  of `200m` means "keep the pods averaging about 100m of CPU each". A
  Deployment whose container states no CPU request gives the autoscaler
  nothing to work with: it cannot compute a percentage, so it cannot decide
  anything. The limit (`500m`) is a ceiling on one pod, not a target.

- **The autoscaler cannot act at all until the metrics API is answering.**
  The HPA controller reads `metrics.k8s.io`, which metrics-server serves
  through an APIService. Until that APIService is `Available` and the pods
  have samples, the HPA reports `<unknown>` for its target and leaves the
  replica count alone. `kubectl top pods` is the quick way to check.

- **The scale-out is not instant.** metrics-server needs a sampling interval
  to produce its first reading, and the autoscaler reconciles on its own
  schedule. Give it a minute or two. The validator waits up to three.

- **The load has to be real.** `while sleep 0.01; do wget -q http://hpa-example; done`
  is about 100 requests a second, and the Apache/PHP app behind the Service
  burns CPU answering them. A single request every few seconds will not push
  the pods past 100m.

- **`kubectl autoscale` and a hand-written manifest produce the same object.**
  `kubectl autoscale deployment hpa-example --name=hpa --min=1 --max=10 --cpu-percent=50`
  writes an `autoscaling/v2` HPA with a `Resource`/`cpu`/`Utilization`
  metric. An `autoscaling/v1` HPA written by hand is converted to the same
  shape when it is stored, so either is accepted.

- **On a kind or minikube cluster metrics-server usually needs two extra
  flags** (`--kubelet-insecure-tls`, and the right
  `--kubelet-preferred-address-types`), or it starts but reports no metrics.
  Check `kubectl -n kube-system logs deploy/metrics-server`.

## Environment requirements

- A cluster with at least one node, and registry access for
  `registry.k8s.io/hpa-example` and `busybox:1.28`.
- **Network access to the metrics-server release manifest** — the candidate
  installs it from
  `https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml`,
  or from a copy of it. A cluster that already has metrics-server installed
  does not need the download, but this lab's setup removes it on purpose.
- No special CNI. The load generator reaches the Service through the normal
  cluster DNS and the normal Service routing.
