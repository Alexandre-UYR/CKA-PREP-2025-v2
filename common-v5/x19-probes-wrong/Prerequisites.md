# x19 — Two probes, both wrong: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `probe` | `LabSetUp.bash` | The Deployment and the ConfigMap live here, and the task names the namespace. The setup deletes and re-creates the namespace on each run, so a Deployment left over from an earlier attempt cannot answer the validation. |
| 2 | Deployment `probed` — nginx:1.25, 2 replicas, pod labels `app=probed` | `LabSetUp.bash` | The workload under repair. Two replicas, so `readyReplicas == 2` is a real check: one ready pod out of two is still broken. |
| 3 | The container declares the port `http` on 80 | `LabSetUp.bash` | The port the liveness probe has to point at. A named container port lets a probe say `port: http` as well as `port: 80`, and the grader resolves either form against this list. |
| 4 | ConfigMap `nginx-conf`, mounted at `/etc/nginx/cka`, with an `nginx.conf` that answers `GET /` with 200 and 404s every other path | `LabSetUp.bash` | The server has to behave as the task describes. The stock nginx configuration answers unknown paths with the index page, so a probe pointed at `/healthz` would get 200 and would never fail; this configuration makes `/healthz` a real 404 and `/` a real 200. |
| 5 | A `readinessProbe` with `tcpSocket` on port 8000 | `LabSetUp.bash` | Nothing listens on 8000, so the readiness probe fails every time and the pods never become Ready. |
| 6 | A `livenessProbe` with `httpGet` on port 80 path `/healthz`, `initialDelaySeconds: 5`, `periodSeconds: 10`, `failureThreshold: 30` | `LabSetUp.bash` | The server does not serve `/healthz`, so every liveness check fails. The kubelet kills the container after roughly 5 + 10 x 30 = 305 seconds. The long budget is deliberate: the wrong probe does not kill the container immediately, so a candidate who only checks `kubectl get pods` once may believe the pods are fine. |
| 7 | The Deployment's UID recorded, in `/tmp/cka-lab/x19.dep.uid` | `LabSetUp.bash` | The task forbids deleting and re-creating the Deployment. The grader compares the UID at validate time with the one recorded here. |
| 8 | The pods to be Running but NOT Ready | `LabSetUp.bash` polls for it | The pre-state has to BE the broken state. The setup waits for two Running pods and warns if they somehow became Ready. |
| 9 | Registry access for `nginx:1.25` | the environment | The pods have to pull and start, or there is nothing to probe. |

## What the candidate must produce

| # | Deliverable | Checked by |
|---|---|---|
| A | The Deployment still exists, with the UID recorded at setup | `LabValidate.bash` |
| B | `.status.readyReplicas` is 2, and every pod's `Ready` condition is `True` | `LabValidate.bash` — the live proof that the readiness probe now succeeds |
| C | Every pod is `Running` | `LabValidate.bash` |
| D | Every container's `restartCount` is 0 | `LabValidate.bash` — a liveness probe that keeps failing is what produces a non-zero restart count |
| E | The liveness probe no longer points at something that does not exist: it is gone, it is an exec probe that succeeds, or its httpGet/tcpSocket target answers | `LabValidate.bash` — an exec probe is run inside the container, an httpGet or tcpSocket target is asked through the pod proxy |

## Gotchas

- **A readiness probe decides whether a pod receives traffic; a liveness probe
  decides whether the kubelet kills the container.** They fail in opposite
  directions. A failing readiness probe leaves a perfectly healthy container
  running but keeps the pod out of the Service's endpoints. A failing
  liveness probe kills the container.

- **A long `failureThreshold` buys time, it does not fix anything.** The
  liveness probe here allows 5 + 10 x 30 = 305 seconds before the kubelet
  kills the container. Until then `kubectl get pods` shows a healthy
  `Running` pod, and the question looks like it is about the readiness probe
  alone. Watch the restart count, not the phase.

- **A readiness probe pointing at a port nothing listens on never passes.**
  `tcpSocket: {port: 8000}` is the classic version: the API server accepts
  it, the pod starts, and the pod is simply never Ready. There is no error
  message — the failure is only visible in `kubectl describe pod` and in the
  `Ready` condition.

- **The kubelet probes the pod's IP, not the Service.** The probe goes to the
  pod directly, so a Service in front of the deployment does not change what
  a probe can reach, and a broken Service does not affect the probe.

- **A probe's port may be a number or a container port NAME.** `port: 80` and
  `port: http` are both legal in a probe, and the named form only resolves
  if the container declares a port with that name. A name that is not
  declared is a probe that can never succeed.

- **The stock nginx image answers every unknown path with the index page.**
  `try_files $uri $uri/ /index.html` means `GET /healthz` returns 200 on an
  unmodified nginx container. That is why this lab mounts its own
  configuration, which serves `/` and 404s everything else — otherwise the
  broken liveness probe would quietly pass and the question would have no
  failure to find.

- **Editing the pod template rolls the Deployment.** The new template
  creates a new ReplicaSet and new pods, so the old pods are replaced rather
  than patched. The Deployment's UID does not change, which is how the
  grader tells an edit from a delete-and-re-create.

- **`kubectl edit deployment` is the tool for this.** The pod template can be
  changed in place while the Deployment runs; nothing has to be deleted.

- **Removing the readiness probe is not the same as fixing it.** It makes the
  pods Ready, so the check passes, but it also stops the pod being checked at
  all. Fixing the probe to point at the port the server listens on is the
  better answer, and the grader accepts either.

## Environment requirements

- A cluster with at least one node, and registry access for `nginx:1.25`.
- The API server's pod proxy (`kubectl get --raw .../pods/<pod>:<port>/proxy/`)
  is used to ask the container what it serves. It works on a normal kubeadm,
  kind and k3s cluster; where it is not available the grader falls back to
  checking the probe against the paths the server is known to serve, and says
  so.
- No special components. Probes, the kubelet and the endpoints controller are
  all part of a normal cluster.
