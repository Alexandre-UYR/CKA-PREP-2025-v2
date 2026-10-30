# w6 — Kill the old pods before you make the new ones: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `cka4` | `LabSetUp.bash` | The Deployment lives here and the task names the namespace. |
| 2 | Deployment `proxy` — nginx:1.28, 6 replicas, pod template labels `app=proxy` | `LabSetUp.bash` | The workload being corrected. It has to exist and be healthy, so that "nothing else about it changed" is a checkable claim. |
| 3 | The Deployment's update strategy is the default `RollingUpdate` | `LabSetUp.bash` | This is the first thing that is wrong. The default strategy brings the new pods up before the old pods go down. |
| 4 | The Deployment's own metadata carries NO `client=user` label | `LabSetUp.bash` | This is the second thing that is wrong. The label has to be added to the Deployment object itself. |
| 5 | The Deployment's UID, recorded at setup time | `LabSetUp.bash` | The task says to edit the Deployment in place. The UID is how the grader proves the object was not deleted and recreated. |
| 6 | A writable `/root` on the machine running `kubectl` | the environment | The answer is a file on disk. If `/root` is not writable the candidate cannot produce an answer at all. |
| 7 | `/root/q4.yaml` cleared of any earlier attempt | `LabSetUp.bash` | `rm -f /root/q4.yaml`, so a second run does not pass on a stale file from the first. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | The Deployment's `spec.strategy.type` set to `Recreate` | `LabValidate.bash` |
| B | The label `client=user` on the Deployment's own metadata | `LabValidate.bash` |
| C | The pod template labels still `app=proxy`, and the selector still matching them | `LabValidate.bash` |
| D | 6 replicas of nginx:1.28, all ready | `LabValidate.bash` |
| E | The Deployment's UID unchanged | `LabValidate.bash` — compared against the UID the setup recorded |
| F | `/root/q4.yaml` holding a Deployment whose strategy type is `Recreate` | `LabValidate.bash` |

## Gotchas

- **`Recreate` is the strategy that kills the old pods before creating the new
  ones.** It is the only one of the two that guarantees no two versions of the
  workload run at the same time. `RollingUpdate` — the default — starts the new
  pods first and takes the old ones down afterwards, and on a small cluster
  that can leave you with seven pods for a Deployment that wants six.

- **A `Recreate` strategy must not carry a `rollingUpdate` block.** The API
  server rejects the object outright: *"may not be specified when strategy type
  is 'Recreate'"*. This bites when you edit the file that
  `kubectl get -o yaml` gave you, because that file still holds the
  `rollingUpdate:` block from the default strategy. Delete the whole block, not
  just the `type:` line under it.

- **A strategic merge patch leaves that block behind.** `kubectl patch
  deployment proxy -p '{"spec":{"strategy":{"type":"Recreate"}}}'` uses the
  strategic merge patch by default, which merges the `strategy` map rather than
  replacing it — the stale `rollingUpdate` survives and the API server refuses
  the result. `--type='merge'` is a JSON merge patch, and a JSON merge patch
  replaces the whole `strategy` object, so the block goes with it.

- **The labels on a Deployment and on its pod template are different things.**
  The Deployment's own labels are for selecting the Deployment — they are what
  a `kubectl -l` or a policy rule matches. The template's labels are what a
  Service selects on, and what the pods actually carry. Putting `client=user`
  on the pod template instead of on the Deployment does not satisfy the task,
  and renaming the pods' `app=proxy` label to make room for it breaks the
  selector.

- **The selector is immutable.** If the candidate changes the template's
  `app=proxy` label, the Deployment's selector no longer matches it and the
  API server refuses the update. The pods have to keep `app=proxy`.

- **`kubectl get -o yaml` output goes stale.** The dump carries
  `metadata.resourceVersion`, and the Deployment controller bumps the
  resourceVersion every time it updates the status. Applying an old dump can
  fail with *"the object has been modified; please apply your changes to the
  latest version"*. Apply the file straight away, or take the dump again.

- **Deleting and recreating the Deployment is not "editing it in place".** The
  UID is the proof. `kubectl apply -f` on a file that describes the same
  Deployment keeps the UID; `kubectl delete` followed by `kubectl create` does
  not.

## Environment requirements

- A cluster with at least one schedulable node.
- Registry access for `nginx:1.28`.
- Write access to `/root` for the candidate and for the validator.
- Kubernetes 1.21 or newer. `Recreate` has been available far longer than that;
  the version only matters because the API server's validation of
  `strategy.rollingUpdate` has to be the one described above.
