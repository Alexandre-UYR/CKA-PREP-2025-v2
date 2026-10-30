# Q4 — Resource allocation: prerequisite inventory

This is the "right-size a workload" question. The interesting part is not the
numbers, it is the shape of the pre-state: a pod with **two** containers (an
init container and the main one), a node whose allocatable resources have to be
read, and a deployment whose pods have to fit three-to-a-node on that node.

## Prerequisite inventory

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Deployment `wordpress` in the default namespace, 3 replicas | LabSetUp.bash | The task is about dividing a node between **3** pods, and it ends with scaling back to 3. The replica count is the divisor. |
| 2 | Pod template label `app: wordpress` | LabSetUp.bash | This is how the grader finds the pods (and therefore the node they were scheduled on) after the candidate has scaled to 0 and back. |
| 3 | One init container named `init-setup` (`busybox`, `sh -c "echo 'Preparing environment...' && sleep 5"`) | LabSetUp.bash | The task says "ensure both the init containers and the main containers use exactly the same resource requests and limits". There has to be an init container to compare against. |
| 4 | One main container named `wordpress` (`wordpress:6.2-apache`) | LabSetUp.bash | The main container is the other half of the "exactly the same" comparison. |
| 5 | **No** `resources` block on either container | LabSetUp.bash | The pre-state is an un-sized workload. If requests were already set, there would be nothing to divide. |
| 6 | A node with a known allocatable CPU and memory | The cluster | The grader reads `.status.allocatable` of the node the pods landed on and compares your per-pod request against a third of it. |
| 7 | No `LimitRange` or `ResourceQuota` in the namespace | The cluster | A default LimitRange would silently rewrite your requests and limits, and a ResourceQuota could reject the deployment. Neither should be in the way. |
| 8 | Nothing left over from a previous attempt | LabReset.bash | The reset deletes the deployment, so the next setup recreates it at 3 replicas with no resources. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| 1 | The deployment scaled back to 3 replicas and healthy | `LabValidate.bash`: "Deployment wordpress is scaled back to 3 replicas", "has 3 ready replicas" |
| 2 | `resources.requests.cpu` on every container (init and main) | `LabValidate.bash`: "Container '<name>' sets resources.requests.cpu", "Init container '<name>' sets resources.requests.cpu" |
| 3 | `resources.requests.memory` on every container | `LabValidate.bash`: "... sets resources.requests.memory" (container and init container) |
| 4 | `resources.limits.cpu` on every container | `LabValidate.bash`: "... sets resources.limits.cpu" (container and init container) |
| 5 | `resources.limits.memory` on every container | `LabValidate.bash`: "... sets resources.limits.memory" (container and init container) |
| 6 | Limits >= requests on every container | `LabValidate.bash`: "Container '<name>' limits.cpu is >= requests.cpu", "limits.memory is >= requests.memory" (container and init container) |
| 7 | The init container and the main container declare **identical** requests and limits | `LabValidate.bash`: "Init container and main container have the same requests.cpu / requests.memory / limits.cpu / limits.memory" |
| 8 | A fair share of the node: 3 x per-pod request <= allocatable, and at least half of it | `LabValidate.bash`: "3 pods requesting ... stay inside the node's ... allocatable", "The CPU given out is a fair share of the node", and the same two for memory |

## Gotchas

- **The init container's request does not add to the main container's.** Kubernetes
  computes the pod's request as `max(sum of the app containers, max of the init
  containers)`: init containers run one after another, app containers in
  parallel. One init container and one app container with the same request means
  the pod requests **that** value once, not twice. Dividing as if it were twice
  gives every pod only half a fair share.
- **"Divide the node evenly" is about requests, not limits.** The scheduler
  places pods on the basis of *requests*; limits only matter for throttling and
  for eviction pressure. The grader sums three times the per-pod request and
  compares it with the node's allocatable.
- **Leave the node some headroom.** Three pods at exactly `allocatable / 3`
  request the whole node, and the kube-system pods on that node already request
  a little. The third pod then stays `Pending` and `readyReplicas` never reaches
  3. Anything from about half a fair share up to a full fair share per pod is
  accepted, so leave a little on the table.
- **The limits are what "overhead" means.** Requests tell the scheduler what to
  reserve; limits are the ceiling the container may burst to. So the pattern is
  `requests: <fair share>` and `limits: <a bit more than the request>`, with
  `limits >= requests` on every container.
- **"Exactly the same" for the init and the main container.** The grader compares
  the four values, so `cpu: 300m` in one and `cpu: 0.3` in the other is fine
  (same value), but `requests.cpu: 300m` and `limits.cpu: 400m` on one
  container and the same requests with different limits on the other is not.
- **Scaling to 0 does not free the pod template.** The requests and limits live
  in `spec.template.spec`, so they can be edited while the deployment is scaled
  to 0 and the pods do not have to be recreated to pick them up.
- **Scaling back to 3 does not happen by itself.** If the deployment is left at
  0 replicas, `readyReplicas` is 0 and the question fails even with perfect
  resource settings.
- **Memory is not the same as CPU.** The grader converts the node's allocatable
  memory to MiB and compares it with three times your per-pod request. A token
  memory request (say 64Mi) is far below half of the node's memory and fails.

## Environment requirements

- A cluster with a node whose `.status.allocatable.cpu` and
  `.status.allocatable.memory` are meaningful (a single-node cluster is ideal:
  all three pods have to fit on one node).
- No `LimitRange` and no `ResourceQuota` in the default namespace.
- The `wordpress:6.2-apache` and `busybox` images pullable.
- The lab has to run on the machine that has `kubectl` configured, because the
  grader runs there and reads the node from the running pods.
