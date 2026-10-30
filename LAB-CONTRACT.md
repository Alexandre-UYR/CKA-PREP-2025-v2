# The contract for every scenario folder

Read this before writing anything. It is the same for `common-v4` (`w1`..`w20`)
and `common-v5` (`x1`..`x20`), and it matches what `common-v2` and `common-v3`
already do.

## The six files

Each scenario folder contains exactly these six files:

```
Questions.bash      the task, in exam wording
Prerequisites.md    what the setup creates, why each piece is needed, the gotchas
LabSetUp.bash       provisions the starting state
LabValidate.bash    grades the answer against real cluster state
LabReset.bash       restores the starting state for another attempt
SolutionNotes.bash  the reference answer
```

## Setup — `LabSetUp.bash`

```bash
#!/bin/bash
set -e
```

- **Idempotent.** Running it twice must leave the same starting state. Use
  `kubectl create ... --dry-run=client -o yaml | kubectl apply -f -` rather than
  a bare `kubectl create`, and delete anything a previous attempt left behind
  before recreating it.
- **Deterministic.** No timestamps, no random names, no reliance on the order the
  cluster hands out addresses in.
- **It provisions the pre-state, and waits for it.** Where the pre-state is
  supposed to be broken, poll until it actually is (see `common-v3/v4` — it waits
  for the OOMKilled) and print a warning if it never happened. A setup that
  reports "ready" while the cluster is still healthy teaches the student to trust
  a message they should have checked.
- **It ends with a short summary** of what it created and what the task is.
- Anything the setup writes to disk (a chart, a manifest, a state file) goes
  under `/tmp/cka-lab/`, and the reset removes it.

## Validator — `LabValidate.bash`

```bash
#!/bin/bash
set -uo pipefail
```

`set -uo pipefail` but **not** `-e`, so every check still runs after one fails.
Use exactly these helpers:

```bash
k(){ kubectl "$@"; }
G='\033[32m'; R='\033[31m'; X='\033[0m'
FAILS=0
ok(){ echo -e "${G}PASS${X}  $1"; }
bad(){ echo -e "${R}FAIL${X}  $1"; FAILS=$((FAILS+1)); }
eq(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }
has(){ case "$2" in *"$3"*) ok "$1";; *) bad "$1 (got '$2')";; esac; }
nonempty(){ if [ -n "$2" ]; then ok "$1"; else bad "$1"; fi; }
exists(){ local d=$1; shift; if k get "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
```

You may add:

```bash
note(){ echo -e "      NOTE  $1"; }   # information, never a failure
skip(){ echo -e "      SKIP  $1"; }   # the environment cannot support this check
```

A SKIP **never** increments `FAILS`. Use it for anything that needs a component
the cluster may not have (metrics-server, a NetworkPolicy-enforcing CNI, a
control-plane node).

One check per imperative in the task. Each failed line must say what it found
and what it wanted. End with:

```bash
if [ "$FAILS" -eq 0 ]; then echo -e "${G}w<N> PASSED${X}"; else echo -e "${R}w<N> FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
```

(`x<N>` in `common-v5`.)

**Grade the outcome, not the method** — several tasks can be solved more than
one way. **But grade a stated constraint.** When the task says "do not delete
the PV", "without recreating the Service", "keep a memory limit", or "do not
raise backoffLimit above 2", that constraint is part of the answer and must be
checked. The usual way is to capture a UID, a limit or a count at setup time and
compare it afterwards.

**Prove behaviour where you can.** A check that reads the object proves the
object is right. A check that runs a probe pod, curls a Service or asks the API
server to reject a Pod proves the behaviour is right. Where the task's point is
the behaviour, prefer the live check.

## Reset — `LabReset.bash`

```bash
#!/bin/bash
set -uo pipefail
```

- `--ignore-not-found` everywhere, safe to run twice.
- Removes everything the setup created **and** anything the candidate was
  supposed to produce, so the next attempt starts from nothing.
- Undoes what a namespace deletion does not: a PersistentVolume with the `Retain`
  reclaim policy survives its namespace, a `hostPath` directory survives on the
  node, a cordoned node stays cordoned, a taint the setup added stays, and a file
  handed to the candidate stays.
- Leaves alone what belongs to the cluster rather than to the question — a
  control-plane taint that kubeadm put there, for example.
- Ends with a one-line confirmation of what it removed.

## Prerequisites — `Prerequisites.md`

First line: `# w<N> — <Title>: prerequisite inventory` (or `x<N>`).

Then, in this order:

1. A table `| # | Prerequisite | Created by | Why the question needs it |` —
   every object the setup creates, and what it is for.
2. A table `| # | Deliverable | Checked by |` — what the candidate has to
   produce, and which check grades it.
3. `## Gotchas` — the traps, and why each one bites.
4. `## Environment requirements` — what the cluster needs for this to work.

Plain, concrete voice. No emoji. British-leaning neutral English. No marketing
language, no "in this comprehensive lab we will".

## Task — `Questions.bash`

First line is the question title. Then the task in exam wording: what is wrong,
what to do, and what "done" means. Write it the way the exam writes it — short
sentences, imperative, no hints about the solution unless the task itself
contains them.

## Solution — `SolutionNotes.bash`

The reference answer, in the order a person would do it, with the commands and
enough explanation of *why* each one is the right one. Not a bare answer key —
see `common-v3/v4/solution.md` for the voice.

## Hard constraints

- **bash 3.2.** These scripts run on macOS as well as on Linux nodes. No
  `${var,,}`, no `${var^^}`, no `mapfile`/`readarray`, no `declare -A`. Use `tr`
  to fold case. Do not assume GNU-only flags.
- **Do not run kubectl. Do not start a cluster. Do not execute the scripts.** The
  machine has no cluster on purpose. Write files only, and verify with `bash -n`.
- `chmod +x` the three `Lab*.bash` files.
- Touch only the folders you were given.

## Where things come from

The `common-v4` and `common-v5` questions are derived from a CKA training course
(PluralSight / Capgemini, Kubernetes CKA v1.32.0) and its lab exercises. They are
original practice scenarios written against the CKA curriculum and the official
Kubernetes documentation — not official exam content, and not course material
copied verbatim. Where the course mentions a specific product (Traefik, cert-manager,
the nfs-csi driver, the local-path provisioner), the question uses it because it
is what the course teaches, but the task, the pre-state and the checks are written
for this lab.
