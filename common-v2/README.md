# CKA common-v2

A second set of practice questions, covering the CKA curriculum by domain. Same
model as the rest of the repo: each question reproduces the **starting state** of
an exam task, so you can practise answering the task itself.

```
   pre-state            task                 answer            reset
  (already there)  ────────────────▶  (you write this)  ────────────────▶ (back to pre-state)
   LabSetUp.bash                          solve it         LabValidate.bash
```

## Requirements

- `kubectl` pointed at a working cluster (minikube, kind, or a cloud cluster)
- `bash`
- Some questions need extra components — each question's `Prerequisites.md`
  says so under "Environment requirements". The common ones are metrics-server
  (c26, c28), a NetworkPolicy-enforcing CNI (c14), and `helm` (c23).

Local cluster, if you need one:

```bash
minikube start --driver=docker
```

Several questions need **at least two nodes** (c6, c8, c9, c29). On a
single-node cluster they still run, but the answers get less interesting.

## Usage

```bash
./lab.sh list                      # the questions
./lab.sh c1 setup                  # provision the environment
./lab.sh c1 task                   # read the question
./lab.sh c1 prerequisites          # what setup just created and why
#   ...solve it...
./lab.sh c1 validate               # PASS/FAIL, one line per check
./lab.sh c1 reset                  # wipe it for another attempt
./lab.sh c1 solution               # the reference answer
```

`<q>` can be `1`, `c1`, `C1` or any part of the question's slug — `gateway`,
`networkpolicy`, `kustomize` all work.

`validate` prints one line per check and a final `c1 PASSED` / `c1 FAILED (n
checks)`. A failed line tells you what it found and what it wanted, so it
doubles as a hint. The exit code is non-zero on failure.

## The questions

### Basic resource creation

| # | Question | What it trains |
|---|---|---|
| c1 | [Multi-container Pod](c1-multi-container-pod/) | Two containers in one Pod, both ready at once, and a live check that one of them works |
| c2 | [Sidecar sharing an emptyDir](c2-sidecar-emptydir/) | Adding a container to a running Deployment, with a volume shared between them |
| c3 | [Service on a named port](c3-named-port-service/) | A Service whose targetPort is a port *name*, and why the container must declare it |
| c4 | [ConfigMap and Secret as files and env vars](c4-configmap-secret-volumes/) | The two ways to consume configuration, and using both at once |

### Cluster operations

| # | Question | What it trains |
|---|---|---|
| c5 | [Bring a NotReady node back](c5-notready-node-kubelet/) | Diagnosing a node from the cluster, then restarting and enabling the kubelet |
| c6 | [Taint and untaint](c6-taint-untaint-node/) | Removing a taint, and why a toleration alone is not enough |
| c7 | [Prepare a node join](c7-kubeadm-join-token/) | The three things a `kubeadm join` command needs |

### Scheduling

| # | Question | What it trains |
|---|---|---|
| c8 | [Place a Pod on a specific node](c8-nodeselector-nodename/) | `nodeName` bypasses the scheduler, `nodeSelector` goes through it |
| c9 | [Spread pods across nodes](c9-topology-spread/) | `topologySpreadConstraints`, and `ScheduleAnyway` versus `DoNotSchedule` |

### Storage

| # | Question | What it trains |
|---|---|---|
| c10 | [Expand a PersistentVolumeClaim](c10-pv-pvc-resize/) | Volume expansion, and the StorageClass that has to allow it |
| c11 | [Dynamic provisioning](c11-storageclass-dynamic-provisioning/) | StorageClasses, the default class, and `WaitForFirstConsumer` |
| c12 | [The four everyday volume types](c12-volume-types/) | emptyDir, configMap, secret and hostPath, and how each appears inside the Pod |

### Networking

| # | Question | What it trains |
|---|---|---|
| c13 | [Ingress with several rules](c13-ingress-rules/) | Hosts, paths, pathTypes and backends in one object |
| c14 | [Allow ingress from one namespace only](c14-networkpolicy-namespace/) | A NetworkPolicy that admits one namespace and nothing else |
| c15 | [The three Service types](c15-service-types/) | ClusterIP, NodePort and LoadBalancer, and why a LoadBalancer's external IP may stay pending |
| c16 | [Cluster DNS has stopped working](c16-coredns-troubleshooting/) | CoreDNS reads its configuration at start-up, so the Deployment has to be restarted |
| c17 | [Gateway API basics](c17-gateway-api/) | Installing the CRDs, then a Gateway and an HTTPRoute |

### Security

| # | Question | What it trains |
|---|---|---|
| c18 | [A ClusterRole that grants exactly one verb](c18-clusterrole-create-permissions/) | Least privilege, and proving it with `kubectl auth can-i` |
| c19 | [A Role bound to a ServiceAccount](c19-rolebinding-serviceaccount/) | Namespaced RBAC, and why access stops at the namespace boundary |
| c20 | [Run a Pod with restricted privileges](c20-pod-securitycontext/) | runAsUser, runAsNonRoot, dropped capabilities and the seccomp profile |
| c21 | [Enforce the restricted Pod Security Standard](c21-pod-security-admission/) | Labelling a namespace, and showing a violating Pod being rejected |

### Custom resources

| # | Question | What it trains |
|---|---|---|
| c22 | [Define a CRD and use it](c22-crd-custom-resource/) | Group/version/kind/plural, and where the `required` list actually lives |

### Helm and Kustomize

| # | Question | What it trains |
|---|---|---|
| c23 | [Install a chart and fix it when it fails](c23-helm-install-troubleshoot/) | Helm reports success even when the workload it created is broken |
| c24 | [One base, two environments](c24-kustomize-overlays/) | Overlays, patches, and building the same base for dev and prod |

### Workload management

| # | Question | What it trains |
|---|---|---|
| c25 | [Scale, update, roll back](c25-scale-rollout-rollback/) | Rollout revisions, and what a rollback does and does not undo |
| c26 | [Horizontal autoscaling](c26-hpa/) | HPA spec, and why utilisation is a percentage of the request |

### Monitoring and troubleshooting

| # | Question | What it trains |
|---|---|---|
| c27 | [A pod that will not stay up](c27-crashloopbackoff/) | Reading logs and events, and the fact that most of a pod spec cannot be changed in place |
| c28 | [Find the hottest Pod](c28-highest-cpu-pod/) | `kubectl top` and label selectors |
| c29 | [Count the nodes that are actually usable](c29-count-ready-nodes/) | Ready versus schedulable, and excluding the control plane |

### Environment and context

| # | Question | What it trains |
|---|---|---|
| c30 | [Know where you are before you act](c30-verify-context-node/) | `kubectl config current-context` and `hostname`, before anything else |

## Exam notes worth knowing

These are in the tasks themselves rather than here, but they change how you
work:

- **Each task may start in a new session**, possibly on a different node.
  Bash aliases and shell functions do not survive that. c30 is the question that
  trains the habit.
- **Troubleshooting questions make up a large share of the exam.** Nine of these
  thirty start from something that is broken: c5, c14, c16, c21, c23, c27, and
  the fix-in-place shape of c6, c8 and c25.
- **Time management.** Flag a question you are stuck on, move on, and come back.
  Five to eight minutes per question is a reasonable target.
- **`kubectl explain` and `kubectl api-resources`** are quicker than guessing,
  and they are allowed.
- **Store your answers in files.** `kubectl get ... > file.yaml` beats retyping
  a manifest, and it makes the second attempt cheap.

## Notes

- These are original practice scenarios written against the CKA curriculum and
  the official Kubernetes documentation. They are not official exam content.
- `LabSetUp.bash` is idempotent: you can re-run it after a reset.
- Nothing here has been run against a live cluster yet. If a check turns out to
  be stricter or looser than it should be, that is worth fixing.
