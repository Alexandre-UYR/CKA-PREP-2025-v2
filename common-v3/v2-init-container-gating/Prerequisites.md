# v2 — The app that cannot start: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `init` | `LabSetUp.bash` | The ConfigMap, the Deployment and its pod live here, and the task names the namespace. |
| 2 | ConfigMap `app-config` with the key `config.yaml` holding `mode: production` | `LabSetUp.bash` | The value the file must end up containing. It already exists so the candidate wires it in rather than inventing it — and so the live check has a known value to look for. |
| 3 | Deployment `cfg`, 1 replica, labels `app=cfg` | `LabSetUp.bash` | The workload the candidate has to fix in place. |
| 4 | Container `app`, image `nginx:1.25`, command `cat /etc/app/config.yaml && sleep 3600` | `LabSetUp.bash` | The app's behaviour is fixed by the task: it reads the file and then stays up. Once the file exists, this exact command works — so the candidate does not have to touch the app, only the plumbing around it. |
| 5 | No volumes and no init containers | `LabSetUp.bash` | The fault. `/etc/app/config.yaml` does not exist anywhere, and nothing produces it, so the container exits immediately. |
| 6 | The container has already exited at least once | `LabSetUp.bash` waits for it | The pre-state has to BE the broken state. The setup polls for `lastState.terminated.exitCode` and warns if the container has not crashed yet. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | At least one init container | `LabValidate.bash` |
| B | An `emptyDir` volume on the pod | `LabValidate.bash` |
| C | The init container mounts that `emptyDir` at `/etc/app` | `LabValidate.bash` |
| D | The init container mounts the ConfigMap `app-config` as a volume, so it can read the value | `LabValidate.bash` |
| E | The init container's command writes into `/etc/app` and reads the ConfigMap's key | `LabValidate.bash` |
| F | The main container mounts that same `emptyDir` at `/etc/app` | `LabValidate.bash` |
| G | The main container mounts the ConfigMap too, read-only | `LabValidate.bash` |
| H | The Deployment has one ready replica | `LabValidate.bash` |
| I | `kubectl -n init exec deploy/cfg -- cat /etc/app/config.yaml` prints `mode: production` | `LabValidate.bash` |

## Gotchas

- **An init container's job is to prepare something the main containers need,
  and it must finish successfully before they start.** That is the whole
  question.

- **A file written into an init container's own filesystem is gone by the time
  the main container starts.** The init container has its own writable layer,
  exactly like any other container; when it exits, whatever it wrote into that
  layer is discarded. The file has to be produced into a volume that both
  containers mount — that is why an `emptyDir` is required. A candidate who
  writes the file in the init container's own root filesystem sees a
  successful init container and a main container that still crashes.

- **The ConfigMap cannot be mounted at `/etc/app` in the main container.** The
  `emptyDir` is mounted there, and two volumes at the same mount path in one
  container is rejected by the API server. Mount the ConfigMap somewhere else
  — `/etc/app-source`, `/config`, anything — and mount the `emptyDir` at
  `/etc/app`.

- **The init container must actually read the ConfigMap as a volume.** The
  value lives in the ConfigMap, and a ConfigMap is not visible to a container
  unless it is mounted or injected. An init container that hard-codes
  `mode: production` has solved nothing; the live check would pass, but the
  `emptyDir` and ConfigMap checks would not.

- **The init container has to finish before the main container starts, so it
  has to exit 0.** A command like `cp` with a wrong source path exits
  non-zero, the pod stays in `Init:CrashLoopBackOff`, and the main container
  never runs at all. Read `kubectl describe pod` if that happens.

- **The main container's command does not need to change.** It already reads
  `/etc/app/config.yaml` and sleeps; the file just has to be there when it
  starts.

## Environment requirements

- A cluster with at least one node, and `kubectl` in the current context.
- Registry access for `nginx:1.25`.
- `kubectl exec` has to work into the main container, which it does by default
  on a local cluster and on most managed ones.
- No special components: this is plain init-container and volume plumbing.
