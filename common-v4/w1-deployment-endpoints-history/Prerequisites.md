# w1 — What the cluster actually says: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `cache` | `LabSetUp.bash` | The Deployment and the Service both live here, and the task names the namespace. |
| 2 | Deployment `cache` — memcached, 3 replicas, labels `app=cache`, container port 11211 | `LabSetUp.bash` | The workload whose rollout history is being asked for. It has to exist and be healthy, or there is no history to read. |
| 3 | Service `cache` — NodePort, port 11211 → targetPort 11211, selector `app=cache` | `LabSetUp.bash` | The object whose endpoints are being asked for. It has a `nodePort` so that the task can also check the port is stable. |
| 4 | The Deployment's pods carry the label `app=cache`, matching the Service's selector | `LabSetUp.bash` | This is what makes the endpoints non-empty. The whole first half of the question is about a Service that resolves to something. |
| 5 | A writable `/root` on the machine running `kubectl` | the environment | Both answers are files on disk. If `/root` is not writable the candidate cannot produce an answer at all. |
| 6 | The two answer files cleared of any earlier attempt | `LabSetUp.bash` | `rm -f /root/q3.json /root/q3.txt`, so a second run does not pass on a stale answer from the first. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | `/root/q3.json` holding the Service's endpoints as JSON | `LabValidate.bash` — exists, non-empty, parses as JSON, and contains every address the Service resolves to |
| B | The Deployment scaled to 5 replicas, all ready | `LabValidate.bash` |
| C | `/root/q3.txt` holding the Deployment's rollout history | `LabValidate.bash` — exists, non-empty, lists at least 2 revisions, mentions the deployment |
| D | The Service still selects the pods and still has its nodePort | `LabValidate.bash` |

## Gotchas

- **A Service exists whether or not it selects anything.** The object, the nodePort
  and the port all look right when the selector matches no pods. What tells you it
  is broken is that its endpoints are empty. That is why the grader counts the
  endpoint addresses rather than just checking the Service object.

- **The endpoints have to match what the Service resolves to NOW.** If the
  candidate writes the endpoints file before scaling, the file holds three
  addresses and the Service now has five — so the file is stale and the grader
  says so. The order of the task matters, and the task states it.

- **`kubectl get endpoints` still works, but EndpointSlices are the modern
  object.** Both carry the same addresses. The grader reads the Endpoints
  resource and falls back to the EndpointSlice if it is not available.

- **A rollout history has a revision per pod-template change, not per scale.**
  Scaling the Deployment does change the pod template's replica count but not its
  template hash, so it may or may not add a revision depending on the version.
  That is why the grader asks for at least two revisions rather than an exact
  count — the history must show the Deployment's history, not a fixed number of
  lines.

- **The JSON has to be JSON.** `kubectl get endpoints -o json` gives it;
  redirecting the plain output gives you a table, which is not JSON. The grader
  checks the shape as well as the contents.

## Environment requirements

- A cluster with at least one node, and registry access for `memcached`.
- Write access to `/root` for the candidate and for the validator.
- No special components. This is a plain Deployment and a plain Service.
