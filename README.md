# CKA Practice (Simple Edition)

Straightforward CKA practice labs derived from the CKA-PREP playlist. Every question
lives in its own folder with the environment it starts from, the task, and an
automatic PASS/FAIL checker.

## The model

Every CKA task is really four things, and the exam only ever shows you two of them:

```
   pre-state            task                 answer            reset
  (already there)  ────────────────▶  (you write this)  ────────────────▶ (back to pre-state)
   LabSetUp.bash                          solve it         LabValidate.bash
```

The exam hands you the **pre-state** and the **task**, and grades the **answer**.
Everything else — what the pre-state should contain, how to rebuild it, and how to
tell whether the answer is right — is the part the exam does not give you, and the
part that is worth rehearsing.

## How to use it

```bash
./lab.sh list                    # the questions
./lab.sh q1                      # provision the environment for question 1
./lab.sh q1 task                 # read the question
#   ...solve it...
./lab.sh q1 validate             # PASS/FAIL, one line per check
./lab.sh q1 reset                # wipe it for another attempt
```

`<q>` can be `1`, `q1`, `Question-1` or part of the folder name (`mariadb`).
Other actions: `prerequisites` (the analysis of what was set up and why) and
`solution` (the reference answer).

`validate` prints one line per check and a final `Q1 PASSED` / `Q1 FAILED (n checks)`.
A failed line tells you what it found and what it wanted, so it doubles as a hint.

## Three sets of questions

This folder holds **three** sets, all built the same way:

| Set | Runner | Questions | What it is |
|---|---|---|---|
| The original set | `./lab.sh` | `Question-1` … `Question-17` | The questions this repo started with, each with its setup, task and solution notes. |
| [`common-v2/`](common-v2/) | `common-v2/lab.sh` | `c1` … `c30` | A broad sweep across the curriculum (resource creation, cluster operations, scheduling, storage, networking, security, CRDs, Helm and Kustomize, workload management, monitoring and troubleshooting, and exam environment habits), organised by domain. |
| [`common-v3/`](common-v3/) | `common-v3/lab.sh` | `v1` … `v20` | The hard set. Every question starts from a cluster that is already broken or half-built, so the work is diagnosis rather than construction. |

The sets do not overlap. The original set goes deep on the individual tasks from
the CKA-PREP playlist, `common-v2` teaches the shapes of things, and `common-v3`
is the diagnosis pass. Work them in that order.

Each set has its own runner, because the folders are named differently:

```bash
./lab.sh q1 setup            # the original set
./lab.sh q1 validate

cd common-v2 && ./lab.sh c1 setup     # common-v2
cd common-v3 && ./lab.sh v1 setup     # common-v3
```

## The original set

| Question | Topic | Needs |
|----------|-------|-------|
| [Question-1](Question-1%20MariaDB-Persistent%20volume) | MariaDB: re-create a Deployment on a retained PV | a cluster with a `hostPath` volume |
| [Question-2](Question-2%20ArgoCD) | Install Argo CD with Helm, CRDs excluded | `helm`, the Argo CD CRDs pre-installed |
| [Question-3](Question-3%20Sidecar) | Add a sidecar container sharing a volume | — |
| [Question-4](Question-4%20Resource-Allocation) | Requests and limits split evenly across a node | — |
| [Question-5](Question-5%20HPA) | HPA with a scale-down stabilisation window | metrics-server |
| [Question-6](Question-6%20CRDs) | List CRDs and `kubectl explain` a field | the cert-manager CRDs |
| [Question-7](Question-7%20PriorityClass) | PriorityClass one below the highest, applied to a Deployment | — |
| [Question-8](Question-8%20CNI%20%26%20Network%20Policy) | Install a CNI that enforces NetworkPolicy | a disposable cluster |
| [Question-9](Question-9%20Cri-Dockerd) | Install and configure cri-dockerd | root on a node |
| [Question-10](Question-10%20Taints-Tolerations) | Taint a node and tolerate it | — |
| [Question-11](Question-11%20Gateway-API) | Migrate an Ingress to Gateway API | the Gateway API CRDs |
| [Question-12](Question-12%20Ingress) | NodePort Service plus an Ingress | an ingress controller (optional) |
| [Question-13](Question-13%20Network-Policy) | Pick the least permissive NetworkPolicy | a CNI that enforces policies |
| [Question-14](Question-14%20Storage-Class) | Create a StorageClass and make it the only default | — |
| [Question-15](Question-15%20Etcd-Fix) | Repair a kube-apiserver pointed at etcd's peer port | control-plane node access |
| [Question-16](Question-16%20NodePort) | Expose a Deployment on a NodePort | — |
| [Question-17](Question-17%20TLS-Config) | TLSv1.3 only, plus an `/etc/hosts` entry | node access for `/etc/hosts` |

Questions 8, 9 and 15 run **on the node**, not through `kubectl`. Question 15
deliberately takes the API server down, so nothing that talks to the cluster will
work until it is fixed.

## What is in a question folder

```
Question-1 MariaDB-Persistent volume/
  LabSetUp.bash       provisions the starting state
  Questions.bash      the task, in exam wording
  LabValidate.bash    grades your answer against the real cluster state
  LabReset.bash       restores the starting state for another attempt
  Prerequisites.md    what the setup creates, why each piece is needed, and the gotchas
  SolutionNotes.bash  the reference answer
```

`Prerequisites.md` is the one worth reading first. It is the answer to "what has
to be there before I can even attempt this question", written out object by
object, and it is where the reasoning lives.

`APPROACH.md` explains the method behind all of it: how to derive the
prerequisites from a question, how to write a checker that grades the outcome
rather than the method, and what a reset has to undo that a namespace deletion
does not.

## Getting into the environment

1. Launch a CKA playground, or point `kubectl` at your own cluster
   (minikube, kind, or a cloud cluster).
2. Clone this repo on the machine that has `kubectl`.
3. Run `./lab.sh q1` to build the environment and read the question.

```bash
alias k=kubectl
export do="--dry-run=client -o yaml"
```

## Notes

- These are original practice scenarios written against the CKA curriculum and the
  official Kubernetes documentation. They are not official exam content.
- Some questions need extra components (metrics-server, the Gateway API CRDs, the
  cert-manager CRDs, an ingress controller, a NetworkPolicy-enforcing CNI). Each
  question's `Prerequisites.md` says so under "Environment requirements".
- `LabSetUp.bash` is idempotent: you can re-run it after a reset.
- Time yourself. Five to eight minutes per question is a reasonable target, and
  use only the official Kubernetes documentation while you work.
