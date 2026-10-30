# w2 — Three Services, one of them broken: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `svcs` | `LabSetUp.bash` | Every object in the question lives here, and the task names the namespace. The setup deletes and re-creates the namespace on each run, so an earlier attempt cannot answer the validation on its own. |
| 2 | Deployment `web` — nginx:1.25, 2 replicas, pod labels `app=web`, container port 80 | `LabSetUp.bash` | The workload all three Services have to select. It has to be healthy, or a Service with the right selector still has nothing to point at. |
| 3 | Service `web-clusterip` — ClusterIP, port 80 → targetPort 80, selector `app=web-v2` | `LabSetUp.bash` | The broken half of the question. The selector matches no pod, so the Service resolves to nothing while looking perfectly correct in `kubectl get svc`. |
| 4 | The Service's UID recorded on the namespace as the annotation `cka-lab/original-service` | `LabSetUp.bash` | The task says to fix the Service in place. A deleted-and-re-created Service gets a new UID, so this is how the grader tells a repaired Service from a replaced one. |
| 5 | The setup waits until `web-clusterip` really has no endpoints | `LabSetUp.bash` | A setup that reports "ready" while the Service is still healthy teaches the candidate to trust a message they should have checked. If the Service still has endpoints when the wait is over, the setup says so. |
| 6 | NodePort 30080 free on the cluster | the environment | The task fixes the nodePort at 30080. If another Service already holds it, the candidate cannot create `web-nodeport` and the setup warns about it. |
| 7 | A writable `/root` on the machine running `kubectl` | the environment | Not needed for this question — no file is graded — but the candidate usually writes one anyway while working. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | `web-clusterip` repaired: still the same object (same UID), with a selector that matches the pods' labels | `LabValidate.bash` — the UID is compared with the one recorded at setup time, and the selector is compared with the pods' labels |
| B | Service `web-nodeport` — NodePort, port 80 → targetPort 80, nodePort 30080, selecting the pods | `LabValidate.bash` — type, both ports, the nodePort, the selector, and the endpoints |
| C | Service `web-lb` — LoadBalancer, port 80 → targetPort 80, selecting the pods | `LabValidate.bash` — type, both ports, the selector, and the endpoints |
| D | All three Services have endpoints | `LabValidate.bash` — at least 2 endpoint addresses on each, after waiting for the endpoints controller to catch up |

## Gotchas

- **A Service is not a firewall rule and not a container.** Its `selector` is the
  only thing that decides which pods it points at. When the selector matches
  nothing the Service still exists, still has a ClusterIP, still has its port
  — and resolves to nothing. `kubectl get svc` alone will not tell you that;
  `kubectl get endpoints` will.

- **The obvious fix is the wrong shape.** `kubectl edit svc` on the selector,
  or `kubectl patch svc web-clusterip -p '{"spec":{"selector":{"app":"web"}}}'`,
  changes the existing object and keeps its UID. Deleting the Service and
  re-creating it also makes the endpoints work — and the grader catches it,
  because the re-created Service has a new UID.

- **The selector key is `app`, the value is `web`.** The Deployment's pods
  carry `app=web`. The broken Service asks for `app=web-v2`. Matching on the
  wrong value — `app=web` versus `app=web-v2` — is the whole bug.

- **`targetPort` names the port on the pod, `port` names the port on the
  Service.** Both are 80 here, so nothing catches a candidate who swaps them,
  but the grader reads them as the task states them.

- **A NodePort's `nodePort` is not the same field as its `port`.** The Service
  is still on port 80 inside the cluster; 30080 is the port the node listens
  on. They are set independently.

- **The LoadBalancer's EXTERNAL-IP is not graded.** On a cluster with no
  load-balancer implementation — kind, minikube without the MetalLB addon, or
  most bare kubeadm clusters — the EXTERNAL-IP stays `<pending>` for ever and
  no amount of correct work will change it. That is an environment limit, not
  a wrong answer, so the validator does not look at it. The endpoints are what
  prove the Service is wired up correctly.

- **Endpoints take a moment to appear.** The endpoints controller reacts to
  the selector change asynchronously, so the validator waits for the endpoint
  count to settle before it decides. A candidate who checks the endpoints
  immediately after the patch may see an empty list for a second or two.

## Environment requirements

- A cluster with at least one node, and registry access for `nginx:1.25`.
- A nodePort range that includes 30080 (the default 30000-32767 does).
- No special components. This is a plain Deployment and three plain Services.
- The LoadBalancer Service does not need a load-balancer implementation, and
  will not get an EXTERNAL-IP without one.
