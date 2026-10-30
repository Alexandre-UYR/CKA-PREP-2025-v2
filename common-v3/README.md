# CKA common-v3 — the hard set

Twenty questions, each starting from a cluster that is already broken or
half-built. You never build something from nothing; you work out what you are
looking at and fix it. Same six files per question as the other sets.

```
   pre-state            task                 answer            reset
  (already there)  ────────────────▶  (you write this)  ────────────────▶ (back to pre-state)
   LabSetUp.bash                          solve it         LabValidate.bash
```

Use this set after `common-v2`, not instead of it. `common-v2` teaches the
shapes; this one teaches the diagnosis.

## Requirements

- `kubectl` pointed at a working cluster (minikube, kind, or a cloud cluster)
- `bash`
- Kubernetes **1.29 or newer** for v14 (native sidecars — alpha behind a feature
  gate in 1.28, on by default from 1.29, GA in 1.33)
- `helm` for v19
- A CNI that enforces NetworkPolicy for v12

Each question's `Prerequisites.md` says what it needs under "Environment
requirements".

Local cluster, if you need one:

```bash
minikube start --driver=docker
```

## Usage

```bash
./lab.sh list                      # the questions
./lab.sh v1 setup                  # provision the environment
./lab.sh v1 task                   # read the question
./lab.sh v1 prerequisites          # what setup just created and why
#   ...solve it...
./lab.sh v1 validate               # PASS/FAIL, one line per check
./lab.sh v1 reset                  # wipe it for another attempt
./lab.sh v1 solution               # the reference answer
```

`<q>` can be `1`, `v1`, `V1` or any part of the question's slug — `oom`,
`statefulset`, `networkpolicy` all work.

`validate` prints one line per check and a final `v1 PASSED` / `v1 FAILED (n
checks)`. A failed line tells you what it found and what it wanted, so it
doubles as a hint.

## The questions

### Workload behaviour

| # | Question | The state you inherit |
|---|---|---|
| v1 | [Sidecar sharing a volume](v1-sidecar-shared-volume/) | The app writes its log into the container's own filesystem, where no sidecar could ever see it |
| v2 | [Init container gating the start](v2-init-container-gating/) | The app reads a file that nothing produces |
| v3 | [Startup probe for a slow app](v3-startup-probe/) | A liveness probe kills the container before it can finish starting |
| v4 | [OOMKilled](v4-oomkilled-limit/) | The container allocates more memory than its cgroup allows |
| v14 | [Native sidecar](v14-native-sidecar/) | A legacy sidecar that starts in the wrong order and cannot be restarted on its own |

### Scheduling and placement

| # | Question | The state you inherit |
|---|---|---|
| v5 | [Scheduling diagnosis](v5-scheduling-diagnosis/) | A pod that matches no node, on a cluster where one node is cordoned and another is tainted |
| v6 | [StatefulSet and headless Service](v6-statefulset-headless/) | A Deployment where a StatefulSet is what was actually wanted |
| v8 | [DaemonSet on every node](v8-daemonset-control-plane/) | A control-plane node that a DaemonSet will skip unless it tolerates the taint |

### Storage

| # | Question | The state you inherit |
|---|---|---|
| v10 | [A claim that will not bind](v10-pvc-binds-existing-pv/) | A claim and a volume that look compatible and are not |

### Networking

| # | Question | The state you inherit |
|---|---|---|
| v12 | [Ingress and egress policy](v12-networkpolicy-ingress-egress/) | A policy that isolates egress as a side effect of isolating ingress |
| v13 | [Two hosts, two certificates](v13-ingress-tls-rewrite/) | Two certificates that need two separate TLS entries |

### Security

| # | Question | The state you inherit |
|---|---|---|
| v15 | [RBAC escalation](v15-rbac-escalation/) | A read-only service account that can grant itself anything |
| v20 | [Guaranteed QoS](v20-qos-guaranteed-limitrange/) | A LimitRange quietly filling in requests that do not match the limits |

### Configuration and delivery

| # | Question | The state you inherit |
|---|---|---|
| v11 | [Secret rotation](v11-secret-rotation-volume-vs-env/) | A secret rotated underneath a running pod, read two different ways |
| v16 | [ResourceQuota rejection](v16-resourcequota-blocks-deployment/) | An API server that refuses the manifest outright |
| v19 | [Helm subchart values](v19-helm-values-subchart/) | A subchart whose values have to be overridden from the parent |

### Lifecycle and operations

| # | Question | The state you inherit |
|---|---|---|
| v7 | [CronJob](v7-cronjob/) | Nothing yet — but it has to be built against real ConfigMap and ServiceAccount inputs |
| v9 | [PodDisruptionBudget](v9-pdb-disruptions/) | A Deployment with nothing protecting it from voluntary disruption |
| v17 | [A Job that will never finish](v17-job-failing/) | A Job whose pod template cannot be edited |
| v18 | [ReplicaSet adoption](v18-replicaset-adoption/) | Pods that belong to an owner that no longer exists |

## A note on grading

The grade is the outcome, not the method — several of these can be solved more
than one way. But where a question states a constraint ("do not delete the PV",
"do not raise backoffLimit above 2", "keep a memory limit"), that constraint is
graded, usually by capturing a UID or a value at setup time and comparing it
afterwards.

## Notes

- Original practice scenarios written against the CKA curriculum and the official
  Kubernetes documentation. Not official exam content.
- `LabSetUp.bash` is idempotent: you can re-run it after a reset.
- Nothing here has been run against a live cluster yet. If a check turns out to
  be stricter or looser than it should be, that is worth fixing.
