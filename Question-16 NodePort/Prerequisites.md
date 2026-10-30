# Q16 — NodePort: prerequisite inventory

The exam hands you a cluster and a task. This file lists everything that was
already in the cluster when you opened the task, and why each piece is there.

## Prerequisite inventory

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `relative` | `LabSetUp.bash` | The task says "a deployment named nodeport-deployment in the relative namespace", and both the Deployment and the Service you create live in it. |
| 2 | Deployment `nodeport-deployment` (image `nginx`, 2 replicas) in `relative` | `LabSetUp.bash` | The task's first step is to *configure* this deployment, not create it. It must already exist. |
| 3 | **No container ports declared** on that deployment | `LabSetUp.bash` | `kubectl create deployment` produces a pod template with no `ports`. The task's first step — "expose on port 80, name http, protocol TCP" — is only meaningful if the port is missing. |
| 4 | The container is named `nodeport-deployment`, not `nginx` | `LabSetUp.bash` (a side effect of `kubectl create deployment`) | This is the trap in the question. `kubectl create deployment` derives the container name from the deployment name, so the container is `nodeport-deployment` even though the image is `nginx`. Any patch you write must name the container that actually exists. |
| 5 | 2 replicas, so there are 2 pods to expose | `LabSetUp.bash` | Requirement 3 is about exposing the *individual* pods. With one replica you cannot tell "the pods" from "the deployment". The grader checks that the Service's endpoints contain at least 2 addresses. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| 1 | The deployment declares a container port named `http`, `containerPort: 80`, `protocol: TCP` | scanned across **all** containers of the pod template |
| 2 | Service `nodeport-service` exists in namespace `relative` | `kubectl get service nodeport-service -n relative` succeeds |
| 3 | Its `type` is `NodePort` | `spec.type` |
| 4 | Its port is `80`, target port resolves to `80`, protocol is `TCP` | the Service's port entry |
| 5 | Its `nodePort` is `30080` | the Service's port entry |
| 6 | Its selector actually selects the deployment's pods | the Service's endpoints contain at least 2 addresses |
| 7 | It also exposes the individual pods | `spec.publishNotReadyAddresses == true` **or** `spec.externalTrafficPolicy == Local` |

## Gotchas

- **The container is not called "nginx".** `kubectl create deployment
  nodeport-deployment --image=nginx` creates a container named
  **`nodeport-deployment`**; the image name is `nginx`. A patch that names the
  container `nginx` is rejected with
  `patch ... does not contain a container with the name "nginx"`, or worse, it
  is applied to a container list that no longer matches. The grader therefore
  looks for the port on **any** container of the pod template rather than
  assuming a container name. (The repo's `SolutionNotes.bash` patches a
  container named `nginx` and is therefore wrong — do not copy it.)
- **A strategic-merge patch replaces the whole container list.** If you patch
  `spec.template.spec.containers` with a single entry, you are replacing the
  container, not editing it. Keep the real container name, image and command.
- **Requirement 3 is ambiguously worded.** "Configure the new Service to also
  expose the individual pods using NodePort" is usually read as one of:
  - `spec.publishNotReadyAddresses: true` — publish endpoints for pods that are
    not ready yet, so every pod gets its own endpoint; or
  - `spec.externalTrafficPolicy: Local` — only route to pods on the node that
    receives the traffic, i.e. expose the individual local pods.

  The grader accepts **either** one and fails with a message naming both if
  neither is set. Re-read the wording on the exam before you commit to one.
- **A Service with `type: NodePort` and no `nodePort` gets an auto-assigned
  one.** The task asks for exactly `30080`, so set it explicitly.
- **The `nodePort` must be in the default range (30000-32767) and free on
  every node.** 30080 is in range; if something else in the cluster already
  holds it, the Service will not be created.
- **The selector has to match the pod labels.** `kubectl create deployment`
  labels the pods `app: nodeport-deployment`. If your Service's selector does
  not match that, the Service exists but has no endpoints and nothing is
  reachable on 30080.
- **Patching the deployment rolls it.** Changing the pod template creates new
  pods; the old pods are terminated. Wait for the new ones to be Ready before
  checking the endpoints.

## Environment requirements

- **A free nodePort in the 30000-32767 range** (30080 specifically) on the
  cluster. If it is taken, the Service cannot be created.
- **At least one node with a reachable IP**, if you want to test the Service
  with `curl http://<nodeIP>:30080`.
- **No node-level access is needed** for the grading itself. `nodePort` traffic
  is a kubelet/iptables concern, but the checks are all API-server-side.
- **Pods must become Ready** for the endpoints check to see 2 addresses. The
  grader waits up to about a minute for them.
