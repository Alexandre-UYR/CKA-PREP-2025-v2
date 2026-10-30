# w18 — The Service's port is not the container's port: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `web` | `LabSetUp.bash` | The Deployment and the Service both live here, and the task names the namespace. The setup deletes and re-creates the namespace on each run, so a Service left over from an earlier attempt cannot answer the validation. |
| 2 | Deployment `site` — nginx:latest, 5 replicas, pod labels `app=site` | `LabSetUp.bash` | The workload the Service has to select. Five replicas is what makes the endpoint count a real check: a Service that resolves to one pod is still a Service that resolves to something. |
| 3 | The container declares a container port NAMED `http` on port 80 (protocol TCP) | `LabSetUp.bash` | This is the name the Service's `targetPort` has to refer to. A named `targetPort` is resolved against the container's port NAMES, so without a declared name there is nothing for the Service to point at. |
| 4 | The pods carry the label `app=site` | `LabSetUp.bash` | The Service's `selector` has to match this, or the Service resolves to nothing. The selector is the only thing that decides which pods a Service points at. |
| 5 | The setup waits for the Deployment to be available and confirms the named port is there | `LabSetUp.bash` | A setup that reports "ready" while the pods are still starting teaches the candidate to trust a message they should have checked. If the named port is not what the task says it is, the setup says so. |
| 6 | Registry access for `nginx:latest` | the environment | The Deployment's pods have to pull and start, or there are no endpoints to count. |
| 7 | A writable `/root` on the machine running `kubectl` | the environment | Not needed for this question — no file is graded — but the candidate usually writes one anyway while working. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | Service `site-svc` in namespace `web` | `LabValidate.bash` — it exists |
| B | The Service's port is named `http` | `LabValidate.bash` — `.spec.ports[0].name` |
| C | The Service's port is 8080 | `LabValidate.bash` — `.spec.ports[0].port` |
| D | The Service's targetPort is the STRING `http` | `LabValidate.bash` — `.spec.ports[0].targetPort` is compared as text, so the number 80 does not pass |
| E | The Service's selector matches the pods' labels | `LabValidate.bash` — every selector entry is compared with the pod template's labels |
| F | The Service has endpoints | `LabValidate.bash` — at least 5 endpoint addresses, after waiting for the endpoints controller to catch up |

## Gotchas

- **`port` and `targetPort` are different fields and are routinely different
  values.** `port` is the port clients connect to on the Service; `targetPort`
  is where the traffic is sent on the pod. Here the Service answers on 8080 and
  the container listens on 80. Writing `port: 8080, targetPort: 8080` produces a
  Service that looks plausible and resolves to nothing useful — the pod is not
  listening on 8080.

- **A named `targetPort` is resolved against the CONTAINER's port names.** The
  Service says `targetPort: http`, and the container has to declare a port
  called `http` for that name to mean anything. If the container's port is
  unnamed, or named something else, the Service has no port to forward to and
  its endpoints come back empty. This is why the container port name is part of
  the pre-state and not part of the answer.

- **`targetPort: http` and `targetPort: 80` are not the same field.** The
  first is a string naming a container port, the second is a number. The
  Service's YAML will keep whichever you wrote, and the grader compares the
  value as text: `http` passes, `80` does not. What the traffic actually does
  is the same in this case, because the container's `http` port IS 80 — the
  point of the question is which of the two fields you filled in.

- **A Service port name is not a free-form label.** It has to be at most 15
  characters, may contain only letters, digits and dashes, and must contain at
  least one letter. `http` is fine; `http-metrics-port` is too long, and
  `http_metrics` is not a legal name. The API server rejects a Service whose
  port name breaks these rules, and the error names the field.

- **A Service exists whether or not it selects anything.** The object, the
  port, the name and the targetPort all look right in `kubectl get svc` when
  the selector matches no pod or the targetPort names nothing. What tells you
  it is broken is that its endpoints are empty. That is why the grader counts
  the endpoint addresses rather than just checking the Service object.

- **The Service's selector has to match the PODS' labels, not the
  Deployment's name.** The Deployment is called `site` and its pods carry
  `app=site`, so `selector: {app: site}` works. `selector: {app: site-svc}`
  matches nothing at all.

## Environment requirements

- A cluster with at least one node, and registry access for `nginx:latest`.
- No special components. This is a plain Deployment and a plain Service, and
  the endpoints controller is part of the control plane.
