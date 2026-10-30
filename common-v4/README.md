# CKA common-v4 — build and expose

Twenty questions drawn from a CKA training course: the half of the exam where you
**build** something and put it where other people can reach it. Same six files per
question as every other set in this repo.

```
   pre-state            task                 answer            reset
  (already there)  ────────────────▶  (you write this)  ────────────────▶ (back to pre-state)
   LabSetUp.bash                          solve it         LabValidate.bash
```

## Requirements

- `kubectl` pointed at a working cluster (minikube, kind, or a cloud cluster)
- `bash`
- `helm` for w10 and w16
- Network access to the Helm repositories for w10 and w16

Each question's `Prerequisites.md` says what it needs under "Environment
requirements".

## Usage

```bash
./lab.sh list                      # the questions
./lab.sh w1 setup                  # provision the environment
./lab.sh w1 task                   # read the question
./lab.sh w1 prerequisites          # what setup just created and why
#   ...solve it...
./lab.sh w1 validate               # PASS/FAIL, one line per check
./lab.sh w1 reset                  # wipe it for another attempt
```

`<q>` can be `1`, `w1`, `W1` or any part of the question's slug — `helm`,
`kustomize`, `daemonset` all work.

## The questions

### Workloads

| # | Question | What it asks for |
|---|---|---|
| w1 | [What the cluster actually says](w1-deployment-endpoints-history/) | The Service's endpoints as JSON and the Deployment's rollout history, in files |
| w3 | [A Pod with two containers](w3-two-container-pod/) | Two named containers, a label, and a command long enough to still be running later |
| w6 | [Kill the old pods first](w6-recreate-strategy/) | The `Recreate` strategy, a label on the Deployment, and the spec saved to a file |
| w7 | [One pod on every node](w7-daemonset-hostpath/) | A DaemonSet with two hostPath volumes, running on the control plane too |

### Services and networking

| # | Question | What it asks for |
|---|---|---|
| w2 | [Three Services](w2-service-types/) | A ClusterIP that selects nothing, fixed in place, plus a NodePort and a LoadBalancer |
| w4 | [The name that does not resolve](w4-service-dns-lookup/) | Why a Service resolves to no address, and the addresses themselves |
| w8 | [A volume with something on it](w8-nfs-pv-pvc/) | A PV and a PVC that bind, a Deployment that mounts them, and the file served |
| w16 | [Get a Host header to the right place](w16-ingress-traefik/) | Traefik installed, an Ingress rule, and a request that proves it |
| w17 | [Move the routing to the new API](w17-gateway-api-migration/) | An Ingress migrated to a Gateway and an HTTPRoute, with the same outside |
| w18 | [The Service's port is not the container's port](w18-service-port-mapping/) | A named targetPort, and a Service port of 8080 pointing at a container port of 80 |
| w19 | [Reachable, but only once it is ready](w19-nodeport-with-readiness/) | A NodePort Service and a readiness probe that gates the traffic |

### Storage, configuration and delivery

| # | Question | What it asks for |
|---|---|---|
| w9 | [A volume that belongs to one Pod](w9-ephemeral-volume/) | A generic ephemeral volume, and proof that the claim belongs to the Pod |
| w10 | [Install a chart, and install it differently](w10-helm-install/) | A Helm release installed with a values file, not by editing the chart |
| w14 | [A ConfigMap made of files](w14-configmap-from-files/) | A ConfigMap built from a directory, and a Pod that exports every key |
| w15 | [The overlay that does nothing](w15-kustomize-fix-overlays/) | A broken Kustomize overlay fixed, a prod overlay written, both previewed before applying |

### Placement and configuration

| # | Question | What it asks for |
|---|---|---|
| w11 | [Bring the nodes back](w11-node-management/) | Uncordon, untaint, and a label that works as a selector |
| w12 | [Three ways of asking to be put somewhere](w12-pod-placement/) | `nodeName`, `nodeSelector` and pod affinity, all on the same node |
| w13 | [The same Secret, two ways](w13-secret-env-and-files/) | A Secret's keys as environment variables AND as files |
| w20 | [One volume, two containers](w20-shared-volume-between-containers/) | A second container reading what the first one wrote |

## A note on grading

The grade is the outcome, not the method — several of these can be solved more than
one way. But where the task states a constraint ("do not delete the Service", "do
not change the pod labels", "keep the same nodePort"), that constraint is part of
the answer and is checked: the setup records a UID at the start and the validator
compares it at the end.

## Notes

- Original practice scenarios written against the CKA curriculum and the official
  Kubernetes documentation, informed by a CKA training course. Not official exam
  content.
- `LabSetUp.bash` is idempotent: you can re-run it after a reset.
- Nothing here has been run against a live cluster yet.
