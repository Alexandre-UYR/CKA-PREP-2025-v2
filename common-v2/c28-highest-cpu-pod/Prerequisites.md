# c28 — Find the hottest Pod: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `metrics` | `LabSetUp.bash` | The task says "in namespace `metrics`". The namespace has to exist before the Pods can be put in it, and the answer is written as `namespace/podname`, so the namespace is part of the answer. |
| 2 | Deployment `cpu-hog` — labels `app=cpu-hog`, `workload=batch` — running `while true; do :; done` | `LabSetUp.bash` | This is the workload that burns CPU. It is the answer, and the label set is what a label selector can find it by. |
| 3 | Deployment `calm-one` — labels `app=calm-one`, `workload=batch` — running `sleep 3600` | `LabSetUp.bash` | A decoy that shares the `workload=batch` label with the hot one. Selecting on `workload=batch` narrows the search to two Pods, and only reading the CPU column tells them apart. |
| 4 | Deployment `calm-two` — labels `app=calm-two`, `workload=web` — running `sleep 3600` | `LabSetUp.bash` | A second decoy, this one outside the `workload=batch` label. It is what makes a too-narrow selector (`workload=batch` alone) look sufficient when it is not, and it is the Pod a careless candidate answers instead. |
| 5 | A CPU request of `100m` on the `cpu-hog` container | `LabSetUp.bash` | It gives the busy-loop container a floor under its measured usage, so the reading is a stable number rather than a blip, and it is what the metrics server reports against. |
| 6 | One replica each | `LabSetUp.bash` | One Pod per Deployment, so the answer is a single Pod name and there is no ambiguity about which Pod of a Deployment is meant. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | `/root/hot-pod.txt` exists | `LabValidate.bash` |
| B | It contains exactly one line | `LabValidate.bash` |
| C | That line is of the form `metrics/<podname>` | `LabValidate.bash` |
| D | The Pod named on that line is the one using the most CPU, per the live `kubectl top pods -n metrics` reading | `LabValidate.bash` — **skipped with a reason if `kubectl top` does not work in this cluster** |
| E | `/root/hot-pod-command.txt` exists and is not empty | `LabValidate.bash` |
| F | The command file records a label selector (`-l` or `--selector`) | `LabValidate.bash` |

## Gotchas

- **A label selector is how you narrow a namespace down to the Pods you
  actually care about before sorting by usage.** `kubectl top pods -n metrics`
  on its own lists every Pod in the namespace; the selector is what turns a
  list into a shortlist. The task asks for the command as well as the answer,
  so the selector is part of what is graded.

- **A selector can narrow too far as well as too little.** `workload=batch`
  matches `cpu-hog` and `calm-one` but not `calm-two`. `app=cpu-hog` matches
  exactly one Pod and is the tightest selector that still finds the answer. If
  a selector returns nothing, widen it; if it returns two, read the CPU
  column.

- **The answer is a Pod name, not a Deployment name.** The Pods that a
  Deployment creates carry a random suffix (`cpu-hog-7d9f4b8c56-x2k9p`), so
  read the name off `kubectl get pods`, not off `kubectl get deployments`.

- **`kubectl top pods` needs a metrics server.** Without one the command
  fails with "Metrics API not available" and there is nothing to measure. If
  that happens, the answer cannot be checked against a live reading, so the
  grader skips that one comparison with a clear reason and still grades the
  file's existence, its format and the command file. It is an environment
  problem, not an answer problem.

- **`kubectl top` shows current usage, which for a busy-loop container is the
  pod's CPU request (or the node's share) rather than a true measurement.**
  The metrics server reports usage against the request, so the number you see
  for a container that is spinning flat out is anchored to its request rather
  than being a genuine measurement of the work it is doing. Treat the value
  as a *comparison* between Pods, not as an absolute figure.

- **The CPU column is not always in millicores.** `kubectl top` prints `15m`
  for a fraction of a core but `1` for a whole core. Sorting the column as
  text puts `9m` above `15m`, and puts `1` below `99m`. Normalise before you
  compare.

- **`kubectl top pods` and `kubectl top pod <name>` can disagree slightly**
  because they are two separate samples taken a moment apart. That is fine
  here: the hot Pod is burning a core and the others are idle, so the
  ordering does not wobble.

## Environment requirements

- A cluster with at least one node and a working scheduler.
- Registry access for `busybox:1.36`.
- **A metrics server (`metrics-server`, or any other implementation of the
  metrics.k8s.io API) for `kubectl top` to work.** This is the one thing
  that decides whether the question can be *measured*. If metrics-server is
  not installed, `kubectl top pods` fails, and the grader skips the
  comparison against the live reading and says so — it does not report a
  failure for something the cluster cannot measure.
- A node with a core to spare: the `cpu-hog` container deliberately spins on
  one core.
- Write access to `/root` for the candidate, since both deliverables are
  written there. The lab expects to run as root.
