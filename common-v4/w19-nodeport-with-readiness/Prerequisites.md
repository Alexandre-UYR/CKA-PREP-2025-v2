# w19 — Reachable, but only once it is ready: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `edge` | `LabSetUp.bash` | The Deployment and the Service both live here, and the task names the namespace. The setup deletes and re-creates the namespace on each run, so a Service left over from an earlier attempt cannot answer the validation. |
| 2 | Deployment `catalog` — nginx:1.25, 2 replicas, pod labels `app=catalog` | `LabSetUp.bash` | The workload the Service has to select and the pod template the readiness probe has to be added to. Two replicas is what makes "only ready pods get traffic" a real question — with one pod there is nothing to hold back. |
| 3 | The container has NO readiness probe | `LabSetUp.bash` | The probe is part of the answer. If the pre-state already had one, there would be nothing to add and the question would be a no-op. |
| 4 | There is NO Service in the namespace | `LabSetUp.bash` | Creating the NodePort Service is the first half of the answer. |
| 5 | The pods carry the label `app=catalog` | `LabSetUp.bash` | The Service's `selector` has to match this, or the Service resolves to nothing. |
| 6 | The setup waits for the Deployment to be available before handing over | `LabSetUp.bash` | The pods have to be running before the candidate adds a probe, so the starting state is real rather than half-built. |
| 7 | NodePort 30080 free on the cluster | the environment | The task fixes the nodePort at 30080. If another Service already holds it, the candidate cannot create `catalog-svc` and the setup warns about it. |
| 8 | Registry access for `nginx:1.25` | the environment | The pods have to pull and start, and the readiness probe has to get a real HTTP response out of them. |
| 9 | A writable `/root` on the machine running `kubectl` | the environment | Not needed for this question — no file is graded — but the candidate usually writes one anyway while working. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | Service `catalog-svc` in namespace `edge` — type NodePort, nodePort 30080, port 80, targetPort 80 | `LabValidate.bash` — type, the nodePort, both ports |
| B | The Service's selector matches the pods' labels | `LabValidate.bash` — every selector entry is compared with the pod template's labels |
| C | The Deployment's pod template has a readiness probe: `httpGet` on path `/` and port 80, `initialDelaySeconds: 2`, `periodSeconds: 5` | `LabValidate.bash` — the four fields are read out of the pod template |
| D | The Service has endpoints | `LabValidate.bash` — at least 2 endpoint addresses, after waiting for the endpoints controller to catch up |
| E | The Deployment has 2 ready replicas | `LabValidate.bash` — `.status.readyReplicas` |
| F | The Service actually serves traffic to the pods | `LabValidate.bash` — a live check: a throwaway pod fetches the Service and has to get the page back |

## Gotchas

- **A readiness probe is what the endpoints controller uses to decide which
  pods appear in the Service's endpoints.** A pod that is not Ready is taken
  out of the Endpoints and stops receiving traffic through the Service. The
  probe is what makes "only ready pods get traffic" true rather than merely
  intended: without it, a pod that has started but is not yet serving is
  handed traffic and the connection is refused.

- **The probe goes on the pod TEMPLATE, not on the running pods.** A readiness
  probe added to a live Pod is rejected — the container list of a running Pod
  is immutable. Add it to `spec.template.spec.containers[0].readinessProbe`
  and the Deployment rolls out new pods with the probe on them. The old pods
  are replaced, and the new ones start unready until the probe first passes.

- **The probe fields are named as the task names them.** `path` and `port` live
  under `httpGet`, not directly under `readinessProbe`. `initialDelaySeconds`
  and `periodSeconds` are siblings of `httpGet`, not children of it. A probe
  written as `readinessProbe: {httpGet: {path: /, port: 80}, initialDelaySeconds: 2}`
  is the right shape.

- **A NodePort is reachable from OUTSIDE the cluster on the node's IP, which a
  ClusterIP is not.** A ClusterIP is only routable from inside the cluster
  network. A NodePort is published on every node's IP on the port you ask for,
  so `http://<node-ip>:30080` reaches the Service from a laptop or from
  another machine. That is what makes it useful for a demo on a laptop and
  wrong for a production ingress.

- **`nodePort` and `port` are different fields.** `port: 80` is what clients
  connect to on the Service; `nodePort: 30080` is the port the node opens up
  for traffic from outside the cluster. The two are routinely different, and
  the task fixes both.

- **The nodePort has to be in the default range, or it has to be requested
  explicitly.** 30080 is inside the default 30000-32767 range, so the API
  server allocates it for you if you leave it out — but then it is not
  30080. The task names the number, so put the number in.

- **A Service exists whether or not it selects anything.** The type, the ports
  and the selector all look right in `kubectl get svc` when the selector
  matches no pod. What tells you it is broken is that its endpoints are empty,
  which is why the grader counts the endpoint addresses.

## Environment requirements

- A cluster with at least one node, registry access for `nginx:1.25`, and
  nodePort 30080 free.
- The live check needs a pod that can reach the Service's ClusterIP from
  inside the cluster, and `busybox:1.36` to run it. If the cluster cannot run
  that pod, the grader skips the live check and says so rather than failing
  the candidate for an environment problem.
- No special components. The readiness probe and the endpoints controller are
  both part of the core cluster.
