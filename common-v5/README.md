# CKA common-v5 — operate, diagnose, secure

Twenty questions drawn from a CKA training course: the half of the exam where you
**diagnose** what is wrong and **operate** the cluster itself. Same six files per
question as every other set in this repo.

```
   pre-state            task                 answer            reset
  (already there)  ────────────────▶  (you write this)  ────────────────▶ (back to pre-state)
   LabSetUp.bash                          solve it         LabValidate.bash
```

These are the questions where the starting state is broken on purpose and the work
is working out what you are looking at.

## Requirements

- `kubectl` pointed at a working cluster (minikube, kind, or a cloud cluster)
- `bash`
- `etcdctl` or `etcdutl` for x2, and a CONTROL-PLANE node — x2 and x3 run on the
  node, not through kubectl
- `helm` for x7, and network access to the cert-manager release manifests
- A CNI that enforces NetworkPolicy for x12
- metrics-server for x13 and x14 (the question asks you to install it)

Each question's `Prerequisites.md` says what it needs under "Environment
requirements".

## Usage

```bash
./lab.sh list                      # the questions
./lab.sh x1 setup                  # provision the environment
./lab.sh x1 task                   # read the question
./lab.sh x1 prerequisites          # what setup just created and why
#   ...solve it...
./lab.sh x1 validate               # PASS/FAIL, one line per check
./lab.sh x1 reset                  # wipe it for another attempt
```

`<q>` can be `1`, `x1`, `X1` or any part of the question's slug — `etcd`,
`networkpolicy`, `cert` all work.

## The questions

### Diagnosis

| # | Question | What is wrong |
|---|---|---|
| x1 | [The pod that will not start](x1-pod-missing-configmap/) | It sources its environment from a ConfigMap that does not exist |
| x6 | [The Service that will never get an address](x6-loadbalancer-pending/) | Nothing in this cluster can give a LoadBalancer an IP |
| x8 | [Cluster names work, the internet does not](x8-dns-forwarding/) | CoreDNS's forwarding plugin is missing |
| x9 | [The manifest that does not do what it says](x9-dodgy-yaml/) | Three separate mistakes in one YAML file |
| x15 | [The Service that selects nothing](x15-service-no-endpoints/) | Its selector does not match the pods' labels |
| x16 | [Two rules that contradict each other](x16-quota-limitrange-conflict/) | The LimitRange's defaults are larger than the quota allows |
| x17 | [The rollout that can never move](x17-rolling-update-deadlock/) | `maxSurge` and `maxUnavailable` are both zero |
| x18 | [The tag that does not exist](x18-imagepullbackoff/) | The image cannot be pulled, and the events say why |
| x19 | [Two probes, both wrong](x19-probes-wrong/) | The readiness probe never passes and the liveness probe will kill the pods |
| x20 | [An object that was never applied](x20-apply-vs-create/) | It was `create`d, not `apply`ed, so there is no last-applied state |

### Operating the cluster

| # | Question | What it asks for |
|---|---|---|
| x2 | [Take a copy of the cluster's brain](x2-etcd-snapshot/) | An etcd snapshot, taken from the control-plane node with the right certificates |
| x3 | [Which log belongs to which component](x3-control-plane-logs/) | The control plane's log files, and who makes scheduling decisions |
| x4 | [Ask the API server directly](x4-kubectl-proxy/) | A namespace list fetched through `kubectl proxy`, not `kubectl get` |
| x5 | [Ten of them, five at a time](x5-job-completions/) | A Job with `completions: 10` and `parallelism: 5` |
| x14 | [Make it work harder, then watch it](x14-hpa-load-generator/) | A metrics server, an HPA, a load generator, and the scale-up |

### Security

| # | Question | What it asks for |
|---|---|---|
| x7 | [A certificate, issued](x7-cert-manager-certificate/) | cert-manager, an Issuer, a Certificate, and the Secret it produces |
| x10 | [nginx as somebody else](x10-nonroot-nginx/) | UID and GID 4242, a port it can bind, and writable paths |
| x11 | [Prove it with the credentials](x11-rbac-token-kubeconfig/) | A Role, a token, a kubeconfig of its own, and the boundary it enforces |
| x12 | [One door open, one door shut](x12-networkpolicy-pair/) | Two NetworkPolicies: one allows, one denies |

### Measuring

| # | Question | What it asks for |
|---|---|---|
| x13 | [Which machine is the busiest](x13-metrics-node-memory/) | A metrics server, the busiest node and the hottest pod |

## A note on grading

The grade is the outcome, not the method. But where the task states a constraint
("do not delete and re-create the Pod", "you may NOT change the quota", "do not
change the ConfigMap"), that constraint is part of the answer and is checked: the
setup records a UID or a spec at the start and the validator compares it at the
end.

Where the question is really about behaviour rather than about YAML, the validator
runs the behaviour — a probe pod that has to be refused, a `printenv` inside a
container, a request that has to come back with 200.

## Notes

- Original practice scenarios written against the CKA curriculum and the official
  Kubernetes documentation, informed by a CKA training course. Not official exam
  content.
- `LabSetUp.bash` is idempotent: you can re-run it after a reset.
- Nothing here has been run against a live cluster yet.
