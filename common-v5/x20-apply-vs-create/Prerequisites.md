# x20 — An object that was never applied: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `traps` | `LabSetUp.bash` | The Service and the Deployment both live here, and the task names the namespace. The setup deletes and re-creates the namespace on each run, so a Service left over from an earlier attempt cannot answer the validation. |
| 2 | Service `svc`, created with `kubectl create service clusterip svc --tcp=80:80` | `LabSetUp.bash` | The object under repair. It exposes port 80 to targetPort 80 and it has **no** `kubectl.kubernetes.io/last-applied-configuration` annotation, because `kubectl create` records nothing about how the object was made. That missing annotation is the whole question. |
| 3 | The Service's selector `app=web`, added with `kubectl patch` | `LabSetUp.bash` | `kubectl create service` leaves the selector empty. The Service has to select the Deployment's pods, and the grader checks that it still does. |
| 4 | Deployment `web` — nginx:1.25, 1 replica, pod labels `app=web` | `LabSetUp.bash` | The workload behind the Service, and the reason a correct Service has an endpoint. The task says the Deployment is not part of the question, so its UID is recorded and compared afterwards. |
| 5 | The Deployment's UID recorded, in `/tmp/cka-lab/x20.dep.uid` | `LabSetUp.bash` | Proves the Deployment was not touched. |
| 6 | A writable `/root` on the machine the validator runs on | the environment | The manifest has to be saved to `/root/svc.yaml`, and the grader has to be able to read it. Where `/root` is not writable, save it somewhere the grader can see and the grader will find it there. |
| 7 | Registry access for `nginx:1.25` | the environment | The pods have to be running, or the Service has no endpoint. |

## What the candidate must produce

| # | Deliverable | Checked by |
|---|---|---|
| A | `/root/svc.yaml` exists and defines the Service `svc` in namespace `traps`, with port 8080 and targetPort 80 | `LabValidate.bash` — the file is parsed by kubectl itself |
| B | The live Service `svc` exposes port 8080 with targetPort 80 | `LabValidate.bash` |
| C | The live Service exposes exactly one port | `LabValidate.bash` — a second, leftover port means the apply merged instead of diffing |
| D | The live Service carries the `kubectl.kubernetes.io/last-applied-configuration` annotation | `LabValidate.bash` |
| E | The JSON inside that annotation agrees with the live Service's ports and selector | `LabValidate.bash` — the annotation is the record of what was applied |
| F | The Service's selector still matches the Deployment's pod labels, and the Service has at least one endpoint | `LabValidate.bash` |
| G | The Deployment is untouched | `LabValidate.bash` — its UID is unchanged |

## Gotchas

- **`kubectl create` records nothing about how the object was made.** It
  writes no `kubectl.kubernetes.io/last-applied-configuration` annotation, so
  there is no record of a configuration that ever existed. `kubectl apply` is
  a three-way merge — the manifest you apply, the configuration it last
  applied, and the live object — and with the middle one missing there is
  nothing to diff against. kubectl says so, and until it has a baseline it
  will not manage the fields you did not mention.

- **A Service's ports are merged by the port NUMBER, not replaced.** This is
  what makes the trap a trap. Applying a manifest whose only port is 8080 to
  a Service that already has port 80 does not replace the port list: the
  strategic merge adds an entry with the key 8080 and leaves the entry with
  the key 80 where it is. The Service ends up exposing **both** 80 and 8080,
  while the annotation records only the manifest that was applied — so the
  annotation and the live object disagree, which is exactly how you notice.

- **The fix is to give kubectl a baseline before applying.** Write a manifest
  that describes the Service as it is now and apply it. That records the
  current state as the last applied configuration, and the next apply can
  then diff against it: the old port 80 is gone from the last applied
  configuration, so the new apply removes it.

- **Do not put the server-generated fields in the baseline.** `clusterIP`,
  `resourceVersion` and `uid` are filled in by the API server. If the last
  applied configuration contains `clusterIP` and the manifest you apply does
  not, the diff tries to delete an immutable field and the API server
  rejects the request. A hand-written baseline with just the name, the
  namespace, the selector and the ports avoids that.

- **An adopted baseline goes stale.** `kubectl get svc svc -o yaml | kubectl
  apply -f -` adopts the live object, but it also changes it — the
  annotation is written and the `resourceVersion` moves on. The copy you took
  before that now carries a stale `resourceVersion`, and the next apply is
  rejected as a conflict. Export it again after adopting it.

- **`kubectl patch` is a different tool for a different job.** It changes one
  field and leaves everything else alone, which is useful, but it does not
  write a last applied configuration — so the object is still one that was
  never applied, and the provenance the task is about is still missing.

- **Deleting the Service and applying it again also produces a correct
  result** — the new object is created by `apply`, so it carries the
  annotation, and it has one port. It costs the Service its clusterIP and
  its age, and it dodges the point of the question rather than answering it.

- **The selector is not part of the port change.** It has to survive. A
  manifest that leaves the selector out removes it, the Service stops
  selecting anything, and its endpoints go empty — a Service with the right
  port and no endpoints is still broken.

- **The Deployment is a decoy.** Nothing in the task requires touching it,
  and the grader compares its UID.

## Environment requirements

- A cluster with at least one node, and registry access for `nginx:1.25`.
- A writable `/root` (or somewhere the grader can read) for the manifest.
- No special components. This is plain Service, Deployment and kubectl
  behaviour.
