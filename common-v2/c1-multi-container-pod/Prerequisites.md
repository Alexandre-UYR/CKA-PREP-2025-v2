# c1 — Multi-container Pod: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `multicontainer` | `LabSetUp.bash` | The task places the Pod in this namespace. The namespace has to exist before the Pod can be created in it. |
| 2 | A cluster with a working scheduler and at least one node that can run `redis:7` and `memcached` | the cluster itself | Both containers have to start, so the images have to be pullable and the node has to have room for the Pod's requests. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | A Pod named `cache` in namespace `multicontainer` | `LabValidate.bash` |
| B | Exactly two containers, named `redis` and `memcached` | `LabValidate.bash` |
| C | The right images (`redis:7`, `memcached`) | `LabValidate.bash` |
| D | Both containers running and ready at the same time | `LabValidate.bash` |
| E | The redis container actually answers a PING with PONG | `LabValidate.bash` (live exec) |

## Why this pre-state is deliberately thin

Most of these questions reproduce a *broken* environment, because that is what
the exam tests. This one does not: the task is to **create** a Pod, so there is
nothing to break. Only the namespace exists.

That is not an oversight, and it is worth recognising when you read the other
questions: a creation task has a thin pre-state by nature, and the difficulty
moves from "diagnose" to "get the shape of the object exactly right". The two
containers, their names, and the fact that they must run *at the same time* are
the whole of the question.

## Gotchas

- **Container names are not the image names.** The API server accepts any name
  you like for a container, but the task asks for `redis` and `memcached` by
  name, and the grader looks them up by name. A Pod whose containers are called
  `c1` and `c2` is a wrong answer even though it runs the right images.

- **Two containers in one Pod share a lifecycle.** There is no restart policy
  per container: if one exits, the Pod is restarted as a whole. That is why the
  grader checks *both* containers are ready rather than just that the Pod
  object exists.

- **`kubectl get pod` shows one READY column for the whole Pod.** It reads
  `1/1` only when every container is ready. A Pod that is `0/2` or `1/2` is
  running but not ready, and the task asks for both containers to be up.

- **Check the container actually works, not just that it started.** The live
  `redis-cli ping` check catches the case where the image starts and then dies
  on a bad argument, which `kubectl get pod` can still show as `Running` for a
  moment.

## Environment requirements

- A cluster with at least one node.
- Registry access for `redis:7` and `memcached`.
- No special components and no CNI with extra features — a plain Pod with no
  networking requirements is enough.
