# c15 — The three Service types: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `svctypes` | `LabSetUp.bash` | All three Services and the Deployment live here. |
| 2 | Deployment `web` (nginx, 1 replica) in `svctypes` | `LabSetUp.bash` | The workload being exposed. The three Services are three different front doors to the same pods. |
| 3 | Label `app=web` on the Deployment and its pods | `LabSetUp.bash` | A Service finds its pods through a selector. The candidate has to write `selector: {app: web}`, and the label has to be there for the endpoints to appear. |
| 4 | Container port 80 on the nginx container | `LabSetUp.bash` | `targetPort: 80` has to point at something. The nginx image listens on 80 by default. |
| 5 | A cluster with a node port range that contains 30080 | the cluster itself | The NodePort Service is asked to publish on 30080 specifically. The default range is 30000-32767, but a cluster can be configured otherwise. |
| 6 | A cluster with a scheduler and one node that can run nginx | the cluster itself | The pods have to be ready for the Services to have endpoints. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | Service `web-clusterip` of type `ClusterIP` | `LabValidate.bash` |
| B | Service `web-nodeport` of type `NodePort` | `LabValidate.bash` |
| C | Service `web-loadbalancer` of type `LoadBalancer` | `LabValidate.bash` |
| D | `port: 80` and `targetPort: 80` on each of the three | `LabValidate.bash` |
| E | `nodePort: 30080` on `web-nodeport` | `LabValidate.bash` |
| F | At least one endpoint address on each of the three | `LabValidate.bash` |

## Gotchas

- **A Service with no selector has no endpoints.** The task does not spell the
  selector out, but without `selector: {app: web}` the Service creates an
  empty Endpoints object and nothing is exposed. The task says "all three must
  actually have endpoints", so the selector is part of the answer even though
  it is not in the list of fields.

- **`port` and `targetPort` are different things.** `port` is the port the
  Service listens on; `targetPort` is the port on the pod that the traffic is
  forwarded to. Here they are both 80, but they are not interchangeable in
  general: a Service on port 80 forwarding to a container on 8080 is a normal
  thing to write.

- **`nodePort` belongs on the port, not on the Service.** It is a field of the
  entry in `spec.ports`, next to `port` and `targetPort`, not a sibling of
  `spec.type`.

- **The type decides who fills the extra fields.** `spec.type: NodePort` makes
  the API server allocate a `nodePort` for you if you leave it out; `spec.type:
  LoadBalancer` makes it ask the cloud provider for an address. The default
  type is `ClusterIP`, so a Service with no `type` field is a ClusterIP.

- **A Service and a Deployment do not have to share a name.** The candidate is
  asked for three Services with three different names, all in front of the same
  `web` pods. Three Services pointing at one Deployment is the whole point of
  the question.

- **`kubectl get svc` shows the type in the TYPE column.** `web-clusterip`
  shows `ClusterIP`, `web-nodeport` shows `NodePort` with a `PORT(S)` entry
  like `80:30080/TCP`, and `web-loadbalancer` shows `LoadBalancer` with an
  `EXTERNAL-IP` column that may say `<pending>`.

## Environment requirements

- A cluster with at least one node.
- Registry access for `nginx`.
- **Node port 30080 must be free.** The default node port range is
  30000-32767, so 30080 is inside it, but if the cluster's range has been
  narrowed or the port is already taken, the NodePort Service cannot be
  created and the question cannot be answered as written.
- **A LoadBalancer Service stays `pending` on a cluster with no load balancer
  implementation.** On `kind` and on plain `minikube` there is no cloud
  controller to allocate an external address, so `web-loadbalancer` keeps an
  empty `EXTERNAL-IP` and `status.loadBalancer.ingress` stays empty. That is
  an environment limitation, not a wrong answer: the grader checks the
  Service's **spec** - type, port, targetPort - and its **endpoints**, and
  deliberately does not look at `.status.loadBalancer.ingress`. A cluster that
  does implement a load balancer (a cloud cluster, MetalLB, or minikube with
  the MetalLB addon) will assign an address, and that is fine too.
- The Endpoints API is deprecated in recent Kubernetes versions. The grader
  reads `kubectl get endpoints` first and falls back to EndpointSlice, so it
  works either way.
