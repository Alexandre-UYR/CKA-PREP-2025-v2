# The approach

How we turn an exam question into something you can practise against.

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

So each question folder carries:

| File | Answers |
|---|---|
| `LabSetUp.bash` | What was already in the cluster when I opened the task? |
| `Questions.bash` | What am I being asked to do? |
| `LabValidate.bash` | Did I actually answer it? |
| `LabReset.bash` | How do I get back to the same starting point for the next attempt? |
| `Prerequisites.md` | *Why* each piece of the pre-state is there — the reasoning, written down. |
| `SolutionNotes.bash` | What a correct answer looks like, to compare against afterwards. |

`Prerequisites.md` is the one that carries the learning. Once you can list the
prerequisites for a question without looking, you can reconstruct the environment in
your head — and reconstructing an environment in your head is exactly what the exam
tests when it hands you a broken cluster.

## Deriving the prerequisites from a question

This is a reading exercise, not a coding one. Work through it in this order.

**1. List every noun in the task that must already exist.**

Read the question and pull out each object it refers to. If the question says "in
namespace `dev`, create a Role", then namespace `dev` is a prerequisite. If it says
"Deployment `webapp` already exists", then `webapp` is. If it says "pod `web` is
stuck", the pod is. Anything the question calls *already*, *still*, *is currently*
or *has* is pre-state. Anything it says *create*, *add*, *scale* or *update* is
yours to build.

**2. Decide the state of each one.**

"Exists" is not a state. For each object, write down the exact state the exam
leaves it in, and make sure that state is *interesting*:

- a healthy `Deployment` with 2 ready replicas, if the task is about a Service;
- a `Deployment` whose image tag does not exist, if the task is about troubleshooting;
- a `PersistentVolume` whose `claimRef` points at a claim that is gone, if the task
  is about recovery.

If you cannot say why a given state is interesting, you have either invented a
prerequisite the question does not need, or you have missed the point of the
question. Both are worth catching here, before the scripts exist.

**3. Check the prerequisites are consistent with each other.**

This is where real exam questions get their difficulty. A PVC that cannot bind
because of a StorageClass mismatch; a Service whose selector no longer matches its
pods; a Pod whose `configMapKeyRef` names a key that does not exist. These are not
accidents — they are the question. If your pre-state has no inconsistency in it,
your pre-state is not doing any work.

**4. Check the pre-state is reproducible.**

Two questions to ask of every line in `LabSetUp.bash`:

- *Is it idempotent?* The exam lets you re-attempt. The setup must be safe to run
  twice, so use `kubectl apply` and `--dry-run=client -o yaml | kubectl apply -f -`
  rather than bare `kubectl create`.
- *Is it deterministic?* No timestamps, no random names, no reliance on the order
  the cluster happens to hand out addresses in. A check that depends on a pod IP is
  a check that will flake.

**5. Check the pre-state is faithful to the exam, not to your convenience.**

The temptation is to build a pre-state that is easy to grade. Resist it. If the
real exam starts with a `Released` PV, yours must be `Released` too — the
difficulty of noticing and fixing that is the whole task.

## Writing the validator

Derive the checks from the task's imperatives, one check per thing the task
demanded. Two rules:

**Check the outcome, not the method.** `kubectl get pvc` is a check. "Did they type
the command I had in mind" is not.

**But do check the constraint when the task states one.** Some questions say "do
*not* delete the Deployment", "without recreating the Service", "the file must have
been written *before* the pod was recreated". Those constraints are graded. The way
to grade them is to capture the object's UID at setup time and compare it at
validate time — if the UID changed, the object was recreated and the task's
constraint was broken.

**Grade the evidence, not the intent.** Where the task asks you to prove something
persisted — "the file must survive" — check the file's timestamp against the pod's
start time, not just that a file exists. A file written after the pod started
proves nothing.

## Writing the reset

Reset has to restore the exact pre-state, which means it has to undo things the
namespace deletion does not undo:

- a `PersistentVolume` with the `Retain` reclaim policy **survives** its namespace.
  Delete it explicitly.
- a `hostPath` directory on the node **survives** everything. Clean it through a
  pod that mounts it, not with `rm` on your laptop.
- a file handed to the candidate, like `~/mariadb-deploy.yaml`, **survives** too.
  Delete it.
- a file the candidate is supposed to produce, like `/root/argo-helm.yaml`, is
  removed so the next attempt starts from nothing.

## Not every question is a kubectl question

Some of these tasks happen **on a node**, not through the API server:

- `Question-8 CNI` and `Question-9 Cri-Dockerd` install things on the machine.
- `Question-15 Etcd-Fix` deliberately breaks the kube-apiserver static pod, so
  `kubectl` does not work at all until it is fixed.

For those, `LabValidate.bash` and `LabReset.bash` run on the node, use `systemctl`,
`sysctl`, `journalctl` and file inspection, and must not assume a working cluster.
`lab.sh` therefore does not check that the cluster is reachable before dispatching —
each script checks only what it needs.

## Conventions

**Setup**

```bash
#!/bin/bash
set -e
```

`set -e` so a failed apply stops the run instead of half-provisioning the
environment.

**Validator**

```bash
#!/bin/bash
set -uo pipefail
k(){ kubectl "$@"; }
FAILS=0
ok(){ echo -e "${G}PASS${X}  $1"; }
bad(){ echo -e "${R}FAIL${X}  $1"; FAILS=$((FAILS+1)); }
eq(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }
has(){ case "$2" in *"$3"*) ok "$1";; *) bad "$1 (got '$2')";; esac; }
nonempty(){ if [ -n "$2" ]; then ok "$1"; else bad "$1"; fi; }
exists(){ local d=$1; shift; if k get "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
```

`set -uo pipefail` but **not** `-e`: the validator must run every check even after
one fails, so you see the whole picture at once. Each failed line names what it
found and what it wanted.

**Reset** uses `set -uo pipefail` and `--ignore-not-found` everywhere, so running
it twice is harmless.

**Node-local state** — `hostPath`, `local`, `nodePort`, `/etc/hosts` and system
services all live on the node, not on the machine you typed the command on.

## A note on the questions themselves

These are original practice scenarios written against the CKA curriculum and the
official Kubernetes documentation. They are not official exam content, and the
environment they run in is not the exam environment. What they *are* good for is
the thing the exam actually tests: reading a task, working out what the cluster
already looks like, and making the change the task asks for.
