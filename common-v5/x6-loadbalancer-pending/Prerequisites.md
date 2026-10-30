# x6 — The Service that will never get an address: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `edge` | `LabSetUp.bash` | The Deployment and the Service both live here, and the task names the namespace. The setup deletes and re-creates the namespace on each run, so nothing survives from an earlier attempt. |
| 2 | Deployment `site` — nginx:1.25, 2 replicas, pod labels `app=site` | `LabSetUp.bash` | The workload behind the Service. Two replicas so that "the Service has endpoints" is a real check rather than a lucky single pod. |
| 3 | Service `public` — type **LoadBalancer**, port 80 -> targetPort 80, selector `app=site` | `LabSetUp.bash` | The object under investigation. On a cluster with no load-balancer implementation it stays `pending` forever. |
| 4 | The annotation `external-dns.alpha.kubernetes.io/hostname: site.example.com` on the Service | `LabSetUp.bash` | A decoy. It is the annotation the external-dns project uses to create a DNS record, and it looks like it should be doing something here. It is not the cause of anything: this cluster has no external-dns controller either. |
| 5 | The Service's UID recorded | `LabSetUp.bash`, into `/tmp/cka-lab/x6.svc.uid` | The task says to edit the Service, not replace it. The grader compares the UID at validate time with the one recorded here, so a delete-and-recreate does not pass. |
| 6 | A verdict on the cluster's load-balancer support | `LabSetUp.bash` | The setup looks for a `service-controller` in the kube-controller-manager's flags, and for an external IP on any LoadBalancer Service in the cluster, and prints which case this is. The task's premise only holds when the cluster has neither. |
| 7 | The setup waits for the Deployment to be available | `LabSetUp.bash` | The pods have to be running before the candidate changes the Service, so the starting state is real rather than half-built. |
| 8 | Registry access for `nginx:1.25` | the environment | The pods have to pull and start, and the live check needs something that answers HTTP on port 80. |
| 9 | NodePort 30080 free on the cluster | the environment | The task fixes the nodePort at 30080. If another Service already holds it, the candidate cannot set it, and the setup warns about it. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | The Service `public` still exists in namespace `edge`, with the UID recorded at setup | `LabValidate.bash` — the UID comparison |
| B | Its type is NodePort | `LabValidate.bash` — `.spec.type` |
| C | Its nodePort is 30080 | `LabValidate.bash` — `.spec.ports[0].nodePort` |
| D | Its port is 80 and its targetPort is 80 | `LabValidate.bash` — both fields |
| E | Its selector still matches the pods' labels | `LabValidate.bash` — every selector entry is compared with the Deployment's pod template labels |
| F | The Service has at least 2 endpoint addresses | `LabValidate.bash` |
| G | A pod inside the cluster reaches the Service on the node's IP and port 30080 and gets HTTP 200 | `LabValidate.bash` (live check) |

## Gotchas

- **A pending external IP is not a bug in the Service.** It is the cluster
  telling you that it has nothing to give the Service an address. On kind, on
  a plain minikube cluster and on a bare kubeadm cluster there is no
  load-balancer implementation at all: no cloud controller manager, no
  MetalLB, no in-tree cloud provider. The Service waits for an address that
  is never going to arrive, and no amount of waiting, restarting or
  re-applying changes that. The fix is to publish the Service a different
  way, not to make the pending state go away.

- **NodePort is the other way to reach a Service from outside.** A NodePort
  is published on every node's own IP, on a port in the 30000-32767 range.
  The node's IP is reachable from outside the cluster, so
  `http://<node-ip>:30080` reaches the Service. A ClusterIP is not: it only
  exists inside the cluster's own network.

- **The `external-dns` annotation is not the missing piece.** The annotation
  `external-dns.alpha.kubernetes.io/hostname` is read by the external-dns
  controller, which creates a DNS record pointing at the Service's external
  address. This cluster has no external-dns controller, and even if it had
  one, it would still have nothing to point the record at until the Service
  had an address. Changing or removing the annotation changes nothing.

- **`type` is a mutable field on an existing Service.** `kubectl patch svc
  public -p '{"spec":{"type":"NodePort"}}'` edits the Service in place; the
  ClusterIP, the selector and the endpoints are all kept. The task says to
  edit it, and the grader checks the UID.

- **Changing the type does not change the endpoints.** The endpoints are
  computed from the selector and the pods, and they were already correct
  while the Service was a LoadBalancer. A candidate who deletes the Service
  and recreates it throws away the UID and has to rebuild the selector and
  the annotation as well.

- **The nodePort is a separate field from the port.** `port: 80` is what
  clients use on the Service; `nodePort: 30080` is the port the node opens
  up for traffic from outside. Both are named in the task, and the two are
  routinely different.

- **Reaching the node's IP from inside the cluster is not always possible.**
  On some CNI setups the node's address is not routable from a pod, so the
  live check cannot be run. The grader says so and skips it rather than
  failing the candidate for an environment problem.

## Environment requirements

- A cluster with at least one node and registry access for `nginx:1.25`.
- Ideally a cluster with no load-balancer implementation, so that the task's
  premise holds. If the cluster does have one, the Service will get an
  external IP and the setup says so; the task is still solvable and the
  grading is unchanged.
- NodePort 30080 free.
- The live check needs `busybox:1.36` and a route from a pod to the node's
  IPv4 address. Where that route does not exist, the grader skips the check
  and prints the reason.
