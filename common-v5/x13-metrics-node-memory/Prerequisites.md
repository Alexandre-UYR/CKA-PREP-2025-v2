# x13 — Which machine is the busiest: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `metrics` | `LabSetUp.bash` | Holds the three Deployments, and is the namespace the hottest Pod has to be reported in. The namespace is re-created on every run, so a leftover from a previous attempt does not survive. |
| 2 | Deployment `hog`, image `busybox:1.36` | `LabSetUp.bash` | The greedy one. It allocates about 64 MiB in a loop, so it is measurably the hungriest Pod in the namespace and it puts its node's memory usage above the others. |
| 3 | Deployments `calm-one` and `calm-two`, image `busybox:1.36` | `LabSetUp.bash` | The quiet ones. They sleep and use a couple of megabytes, so the answer is unambiguous. |
| 4 | **No** metrics server, anywhere | the setup removes any that is there | The failure. `kubectl top` is not part of Kubernetes, so without a metrics API there is nothing to ask. |
| 5 | The `metrics` API server extension registered | installed by the candidate | `kubectl top` talks to `metrics.k8s.io`, which is not a core API. It only exists once a metrics server is installed and running. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | A metrics server Deployment in `kube-system` | `LabValidate.bash` |
| B | `kubectl top nodes` works | `LabValidate.bash` |
| C | `/root/busiest-node.txt` holds the name of the node with the highest memory usage | `LabValidate.bash`, compared with the live `kubectl top nodes` |
| D | `/root/hottest-pod.txt` holds `metrics/<pod>` for the Pod with the highest memory usage in the namespace | `LabValidate.bash`, compared with the live `kubectl top pods -n metrics` |

## Gotchas

- **The metrics API is not part of Kubernetes.** It is an API server
  extension: `metrics.k8s.io` is an aggregated API served by a separate
  component that reads the kubelet's statistics. `kubectl top` has nothing to
  ask until something like metrics-server is installed, running and
  registered. There is no `kubectl top` without it.

- **`kubectl top` reports the CURRENT usage against the container's request.**
  A container with no request can look like it is using nothing: the
  percentage columns are measured against the request, and there is no request
  to measure against. Read the bytes column, not the percentage.

- **The Pod names are not the Deployment names.** `kubectl top pods` lists
  `hog-7d9f4c8b6-2xk4p`, not `hog`. The file has to hold the Pod name.

- **The answer moves.** The Pods are rescheduled and restarted over the life of
  the exercise, so a Pod name written earlier can be stale. The grader
  compares against the live `kubectl top` output at validation time, so the
  file has to be right now.

- **Memory usage is read from the node, not from the Pod.** The busiest node
  is the node the hog landed on - but the node's figure also carries every
  other Pod on it, and the kubelet's own overhead. A node's memory number
  moves around a little, so compare the numbers rather than the order of two
  close nodes.

- **Metrics-server needs a moment.** After it is installed, its Pod has to
  start and the kubelet has to report its first statistics. `kubectl top`
  answers `no metrics available` for the first half-minute or so.

- **The metrics API often has to be told to trust the cluster's
  certificate.** On a cluster with a self-signed kubelet certificate,
  metrics-server refuses to scrape and `kubectl top` never answers. The fix is
  the `--kubelet-insecure-tls` argument on the metrics-server Deployment.

## Environment requirements

- A cluster with at least one node, and registry access for `busybox:1.36`.
- Internet access, or a copy of the metrics-server manifests, for the
  candidate to install it. The upstream manifests are at
  `https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml`.
- The node the hog lands on needs enough memory to take 64 MiB without
  trouble.
- The grader compares against the live `kubectl top` output, so the metrics
  server has to still be running at validation time. If it is not, the two
  comparison checks are skipped and only the files are graded.
