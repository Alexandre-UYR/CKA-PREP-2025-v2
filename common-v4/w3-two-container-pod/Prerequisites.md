# w3 — A Pod with two containers: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `multi` | `LabSetUp.bash` | The Pod has to be created here, and the task names the namespace. The setup deletes and re-creates the namespace on each run, so a leftover `multi-pod` from an earlier attempt cannot answer the validation. |
| 2 | Deployment `single` — nginx:1.16.0, 1 replica, pod labels `app=single` | `LabSetUp.bash` | The worked example of one container. It is deliberately simple and healthy, so the candidate can compare it with what they are asked to build. |
| 3 | The setup waits for `single` to be ready | `LabSetUp.bash` | The example has to be a real, running example rather than a manifest in a file. |
| 4 | Registry access for `busybox:1.36` and `nginx:1.16.0` | the environment | Both images have to be pullable, or the candidate's Pod never starts and the grader cannot tell a broken Pod from a broken image pull. |
| 5 | A writable `/root` on the machine running `kubectl` | the environment | Not needed for this question — no file is graded — but the candidate usually writes one anyway while working. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | Pod `multi-pod` in namespace `multi` | `LabValidate.bash` — it exists and its phase is `Running` |
| B | Exactly two containers, named `busy1` and `busy2`, both from `busybox:1.36` | `LabValidate.bash` — the container list is read from the spec: the count, the names, and the images |
| C | Both containers run a `sleep` of at least 100000 seconds | `LabValidate.bash` — the command and args are read out of the container spec and the number passed to `sleep` is parsed out of them, so `sleep 100` does not pass |
| D | The Pod carries the label `env=test` | `LabValidate.bash` — `.metadata.labels.env` |
| E | Both containers are Ready and neither has restarted | `LabValidate.bash` — `.status.containerStatuses[*].ready` and `.restartCount`, read per container name |

## Gotchas

- **A Pod with two containers shares one network namespace and one lifecycle.**
  The containers talk to each other over `localhost`, they share the Pod's IP,
  and they are started and stopped together. If one container exits, the
  kubelet restarts the whole Pod rather than just that container. So a
  container that runs `sleep 100` does not finish harmlessly — it brings the
  Pod down and starts it again.

- **The container names are part of the answer.** `busy1` and `busy2` exactly.
  A Pod with containers called `busybox` and `busybox2`, or with the second
  container left unnamed, is not what the task asked for.

- **`sleep 100000` is about 27 hours.** The task says the Pod must still be
  running five minutes later, and the grader cannot wait five minutes to find
  out. It reads the number out of the command instead: `sleep 100` fails the
  check even though the Pod is Running right now. `sleep 300` would be long
  enough in practice and still fails the grade, because the task names the
  number.

- **The command has to be in `command`, not in an argument the image ignores.**
  The busybox image's own command is `sh`. If the Pod is written as
  `args: ["sleep", "100000"]` with no `command`, the container runs `sh` with
  those arguments, `sh` tries to execute a file called `sleep`, and the
  container exits immediately. The grader reads `command` and `args`
  together, so it will not let this through either.

- **`restartCount` is the check that says the Pod is not flapping.** A Pod can
  be in phase `Running` and still have restarted its containers several times.
  The grader looks at the restart count as well as the phase.

- **A Pod is not a Deployment.** `multi-pod` is a bare Pod, so nothing
  recreates it if it is deleted or evicted. That is what the task asks for,
  and it is why the grader checks the Pod by name rather than by label
  selector.

## Environment requirements

- A cluster with at least one node, and registry access for `busybox:1.36`.
- No special components. This is a plain Pod with two containers.
