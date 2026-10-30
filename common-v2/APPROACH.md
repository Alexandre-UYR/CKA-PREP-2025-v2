# The approach (common-v2)

This set uses the same method as the rest of the repo — see `../APPROACH.md` for
the full write-up. In short:

```
   pre-state            task                 answer            reset
  (already there)  ────────────────▶  (you write this)  ────────────────▶ (back to pre-state)
   LabSetUp.bash                          solve it         LabValidate.bash
```

The exam hands you the **pre-state** and the **task**, and grades the **answer**.
Everything else — what the pre-state should contain, how to rebuild it, and how
to tell whether the answer is right — is the part worth rehearsing.

## The files in a question folder

```
cN-<slug>/
  Questions.bash      the task, in exam wording
  Prerequisites.md    what the setup creates, why each piece is needed, the gotchas
  LabSetUp.bash       provisions the starting state (idempotent)
  LabValidate.bash    grades the answer against real cluster state
  LabReset.bash       restores the starting state for another attempt
  SolutionNotes.bash  the reference answer
```

## Conventions

**Setup** — `#!/bin/bash`, `set -e`, idempotent (safe to run twice), deterministic
(no timestamps, no random names).

**Validator** — `#!/bin/bash`, `set -uo pipefail` but **not** `-e`, so every check
still runs after one fails. The helper set is fixed:

```bash
k(){ kubectl "$@"; }
FAILS=0
ok(){ echo -e "${G}PASS${X}  $1"; }
bad(){ echo -e "${R}FAIL${X}  $1"; FAILS=$((FAILS+1)); }
eq(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }
has(){ case "$2" in *"$3"*) ok "$1";; *) bad "$1 (got '$2')";; esac; }
nonempty(){ if [ -n "$2" ]; then ok "$1"; else bad "$1"; fi; }
exists(){ local d=$1; shift; if k get "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
```

Plus `note()` for information and `skip()` for checks the environment cannot
support. A SKIP never counts as a failure.

**Reset** — `set -uo pipefail`, `--ignore-not-found` everywhere, safe to run
twice, and it undoes what a namespace deletion does not: retained
PersistentVolumes, node-local `hostPath` directories, `/etc/hosts` entries, and
files handed to the candidate.

**bash 3.2** — these scripts run on macOS as well as on Linux nodes, so no
`${var,,}`, no `mapfile`, no `declare -A`. Use `tr` to fold case.

## Two kinds of pre-state

**Reproduction questions** reproduce a broken environment, because that is what
the exam tests: the CoreDNS ConfigMap with a renamed plugin (c16), the pod that
crash-loops (c27), the cluster with a NotReady node (c5), the chart with an
image that does not exist (c23).

**Creation questions** have a thin pre-state by nature — the task is to create
something, so there is nothing to break (c1, c4, c12, c22). The difficulty moves
from "diagnose" to "get the shape of the object exactly right": the right names,
the right fields, the right apiGroup.

A useful thing to notice while you work through them: the questions that need a
*live* answer — a probe pod that must reach a Service, a `can-i` that must say
no, a pod that must be rejected by admission — are the ones that teach the most,
because they grade the effect rather than the YAML.

## Node-level questions

c5 (kubelet), c7 (kubeadm join) and c30 (hostname) run on a node rather than
through `kubectl`. Their validators inspect the machine, not the API.
