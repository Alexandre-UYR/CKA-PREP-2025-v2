# The approach (common-v3)

This is the **hard** set. It uses the same method as the rest of the repo — see
`../APPROACH.md` for the full write-up — but with two differences in emphasis.

```
   pre-state            task                 answer            reset
  (already there)  ────────────────▶  (you write this)  ────────────────▶ (back to pre-state)
   LabSetUp.bash                          solve it         LabValidate.bash
```

## What makes this set harder

**Every question has a real pre-state.** In `common-v2` a few questions were
creation tasks with a thin environment. Here, every single one starts from a
cluster that is already broken or half-built, and the setup provisions it. You
are never asked to build something from nothing — you are asked to work out what
you are looking at. That is the difference between practising YAML and practising
diagnosis.

**The pre-state is the puzzle, and it is deliberate.** Each one reproduces a real
failure mode rather than a contrived one:

| Question | The state you inherit |
|---|---|
| v1 | The app writes its log into the container's own filesystem, so no sidecar could ever see it |
| v2 | The app reads a file that nothing produces |
| v3 | A liveness probe kills the container before it can finish starting |
| v4 | The container allocates more memory than its cgroup allows |
| v5 | A pod that matches no node, on a cluster where one node is cordoned and another is tainted |
| v6 | A Deployment where a StatefulSet is what was actually wanted |
| v7 | Nothing yet — a CronJob has to be built, but against real ConfigMap and ServiceAccount inputs |
| v8 | A control-plane node that a DaemonSet will skip unless it tolerates the taint |
| v9 | A Deployment with nothing protecting it from voluntary disruption |
| v10 | A claim and a volume that look compatible and are not |
| v11 | A secret rotated underneath a running pod, read two different ways |
| v12 | A policy that isolates egress as a side effect of isolating ingress |
| v13 | Two certificates that need two separate TLS entries |
| v14 | A legacy sidecar that starts in the wrong order (needs Kubernetes 1.29+ — the feature is alpha behind a gate in 1.28 and on by default from 1.29) |
| v15 | A read-only service account that can grant itself anything |
| v16 | An API server that refuses the manifest outright |
| v17 | A Job whose pod template cannot be edited |
| v18 | Pods that belong to an owner that no longer exists |
| v19 | A subchart whose values have to be overridden from the parent |
| v20 | A LimitRange quietly filling in requests that do not match the limits |

## The files in a question folder

```
vN-<slug>/
  Questions.bash      the task, in exam wording
  Prerequisites.md    what the setup creates, why each piece is needed, the gotchas
  LabSetUp.bash       provisions the starting state (idempotent)
  LabValidate.bash    grades the answer against real cluster state
  LabReset.bash       restores the starting state for another attempt
  SolutionNotes.bash  the reference answer
```

## Conventions

**Setup** — `#!/bin/bash`, `set -e`, idempotent (safe to run twice), deterministic
(no timestamps, no random names). Where the pre-state is supposed to be broken,
the setup **waits for the breakage to actually happen** before reporting success,
and warns if it did not. A setup that reports "ready" while the cluster is still
healthy teaches you to trust a message you should have checked.

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
PersistentVolumes, node-local `hostPath` directories, cordoned nodes, taints the
setup added, and files handed to the candidate. Anything the setup cordoned or
tainted must be undone; anything that was part of the cluster's normal state
(a control-plane taint, for instance) must be left alone.

**bash 3.2** — these scripts run on macOS as well as on Linux nodes, so no
`${var,,}`, no `mapfile`, no `declare -A`. Use `tr` to fold case.

## Two things worth remembering before you start

**The grade is the outcome, not the method.** Several of these questions can be
solved in more than one way — the validator checks what the cluster ended up
looking like. Where a question states a constraint ("do not delete the PV", "do
not raise backoffLimit above 2", "keep a memory limit"), that constraint is
graded, and it is usually graded by capturing a UID or a limit at setup time and
comparing it afterwards.

**Time management is part of the exam.** Flag a question you are stuck on, move
on, and come back. Five to eight minutes is a reasonable target, and these
questions are deliberately slower than the `common-v2` ones — that is what makes
them a good second pass, not a first one.
