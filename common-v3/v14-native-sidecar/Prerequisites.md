# v14 — Convert a legacy sidecar into a native one: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `sidecars` | `LabSetUp.bash` | The Deployment and its pod live here, and the task names the namespace. |
| 2 | Deployment `legacy`, 1 replica, labels `app=legacy` | `LabSetUp.bash` | The workload the candidate edits in place. It exists so there is something to convert rather than something to build from scratch. |
| 3 | Container `app`, image `nginx:1.25`, writing to `/var/log/app.log` in a loop | `LabSetUp.bash` | The main container. It has to stay exactly as it is; only the collector moves. |
| 4 | Container `logcollector`, image `busybox:1.36`, command `sh -c 'tail -f /var/log/app.log'` | `LabSetUp.bash` | The subject of the task. It has to keep its image and its command, so the candidate has to move the existing block rather than retype it. |
| 5 | `logcollector` sits in `spec.containers`, next to `app` | `LabSetUp.bash` | This is the fault. A collector in `spec.containers` is a regular container: it starts alongside the app, in an unspecified order, and cannot be restarted on its own. That is the legacy sidecar pattern. |
| 6 | emptyDir volume `shared-logs` mounted at `/var/log` in both containers | `LabSetUp.bash` | The shared state that makes the collector worth having at all. The task says not to change it, so it has to be carried across to the initContainer intact. |
| 7 | The pod is running with both containers ready | `LabSetUp.bash` waits for it | The pre-state has to BE a working legacy sidecar, not a broken Deployment. The setup polls for two ready containers and warns if it has not got there. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | An init container named `logcollector` in `spec.initContainers` | `LabValidate.bash` |
| B | That init container has `restartPolicy: Always` | `LabValidate.bash` |
| C | `spec.containers` holds only `app` — the logcollector moved, it was not copied | `LabValidate.bash` |
| D | The logcollector still uses `busybox:1.36` | `LabValidate.bash` |
| E | The logcollector command still tails `/var/log/app.log` | `LabValidate.bash` |
| F | The `shared-logs` emptyDir still exists | `LabValidate.bash` |
| G | `shared-logs` is still mounted at `/var/log` in the app container | `LabValidate.bash` |
| H | `shared-logs` is still mounted at `/var/log` in the logcollector | `LabValidate.bash` |
| I | The Deployment has one ready replica, and the running pod is the one the current template describes | `LabValidate.bash` |
| J | The pod is `Running` with two ready containers — `app` and `logcollector` | `LabValidate.bash` |
| K | The running pod's logcollector really is a sidecar (`restartPolicy: Always` in the pod's `spec.initContainers`) | `LabValidate.bash` |

## Gotchas

- **The ordering is the point.** A native sidecar is started, and is
  considered STARTED, before the next init container and before the main
  containers run. With the legacy pattern the app may be writing log lines
  before the collector is even listening. A candidate who only shuffles the
  container around without understanding this has not solved anything.

- **A native sidecar is restarted on its own.** If the collector crashes, the
  kubelet restarts it without the whole pod going down. A regular container
  behaves the same way, but a native sidecar additionally keeps running until
  the pod's main containers have finished, and is then terminated
  automatically.

- **The container has to move, not be copied.** Leaving `logcollector` in
  `spec.containers` as well as adding it to `spec.initContainers` gives the
  pod two collectors and defeats the whole point. The validator counts the
  containers in `spec.containers` and fails if there is more than one.

- **The volume mount has to travel with it.** A container in
  `spec.initContainers` uses the same `volumeMounts` syntax as any other
  container. Forgetting to carry `shared-logs` over means the collector tails
  a path that is not the shared one, and the log stays empty. The validator
  checks the mount path on the init container separately from the one on the
  app container.

- **The image and the command are not yours to change.** The task says so.
  `busybox:1.36` and `tail -f /var/log/app.log` are what the validator looks
  for; `tail -F` is not accepted even though it would be the more robust
  command.

- **Where the sidecar's status is reported.** A restartable init container is
  reported under `status.initContainerStatuses`, while an ordinary container
  is reported under `status.containerStatuses`. The validator counts ready
  containers across both lists so it does not depend on which one the
  cluster uses.

- **Editing the Deployment is enough; do not delete it.** Deleting and
  recreating the Deployment would also work, but the task is to convert the
  one that is there. The validator only looks at the Deployment named `legacy`
  in namespace `sidecars`.

## Environment requirements

- **Kubernetes 1.28 or newer.** The native sidecar field — an initContainer
  carrying `restartPolicy: Always` — did not exist before 1.28. It was alpha
  and behind the `SidecarContainers` feature gate in 1.28, enabled by
  default (beta) from 1.29, and went GA in 1.33. So on 1.29 and newer the
  field works out of the box; on 1.28 the gate has to be enabled. `LabSetUp.bash`
  reads the server version and warns clearly if the cluster is older than
  1.28, or if it is exactly 1.28 where the feature gate is required.
- A cluster with at least one node and `kubectl` in the current context.
- Registry access for `nginx:1.25` and `busybox:1.36`.
- No special components: this is plain pod and container plumbing.
