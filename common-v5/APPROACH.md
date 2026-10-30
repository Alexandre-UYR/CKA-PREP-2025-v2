# The approach (common-v5)

The same method as every other set in this repo. The full write-up is in
[`../APPROACH.md`](../APPROACH.md); the file-by-file contract every scenario
folder follows is in [`../LAB-CONTRACT.md`](../LAB-CONTRACT.md).

```
   pre-state            task                 answer            reset
  (already there)  ────────────────▶  (you write this)  ────────────────▶ (back to pre-state)
   LabSetUp.bash                          solve it         LabValidate.bash
```

## What this set is for

`common-v2` teaches the shapes, `common-v3` is the diagnosis pass, and
`common-v4` is the build pass. This set is **operate, diagnose, secure**: the
questions where you are inside the cluster rather than looking at it.

Three kinds of question live here:

**Broken on purpose.** x1, x8, x15, x16, x17, x18, x19 and x20 each start from a
cluster that is genuinely misconfigured, and the symptom is the entry point. The
setup does not just create the objects — it WAITS for the failure to happen
(`ImagePullBackOff`, the pods not Ready, the rollout not moving) and warns if it
never did, so the pre-state is the state the task describes.

**Inside the machine.** x2 and x3 run on the control-plane node, not through
`kubectl` — an etcd snapshot needs the PKI on the node, and the control plane's
log files are on the node's filesystem. Their validators inspect the node, not
the API.

**The boundary.** x10, x11 and x12 are about what a subject is allowed to reach:
a non-root user inside a container, a ServiceAccount inside its own namespace, a
pod that may talk to one thing and not another.

## The rules that keep a diagnosis question honest

**Reproduce the failure, do not describe it.** A setup that creates a broken
object and calls the environment ready is teaching the student to trust a
message they should have checked. Every broken pre-state here polls for the
actual symptom and says so when it is not there.

**Grade the constraint, not just the fix.** x1 forbids re-creating the Pod, x16
forbids changing the quota or the LimitRange, x18 forbids changing the
ConfigMap. The setup records a UID or a spec at the start; the validator compares
it at the end. A candidate who deleted the Pod and re-created it with the right
env var has solved nothing.

**Grade the behaviour where the task's point is the behaviour.** A Pod that is
Running but has no `MODE` in its environment has not been fixed, so x1 execs into
it. A NetworkPolicy that allows everything has not worked, so x12 makes a request
that must be refused. Where the environment cannot support the live check —
NetworkPolicy without an enforcing CNI, metrics without a metrics server — the
check SKIPs with a clear reason and the object checks still count.

**Say when the answer is "nothing to fix".** x6 is a question whose correct
answer is that the LoadBalancer Service is behaving exactly as designed, and
that the fix is a different Service type rather than a fix. Not every pending
object is a fault.
