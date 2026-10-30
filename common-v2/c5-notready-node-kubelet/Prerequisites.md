# c5 — Bring a NotReady node back: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | A cluster with a control-plane node and at least one worker node | the cluster itself | The task says *one of the worker nodes* has become NotReady. There has to be a worker to break, and a control plane to keep running while it is broken. |
| 2 | One worker node whose kubelet has been stopped | `LabSetUp.bash` | A NotReady node is almost always a kubelet or container-runtime problem, not a spec problem. The kubelet is the thing that reports the node's heartbeat to the API server; stop it and the node stops reporting. |
| 3 | The name of that node, written to `/tmp/cka-lab/c5.node` | `LabSetUp.bash` | The grader has to know which node was broken. The file is how it finds out; without it, the grader falls back to "whichever node is NotReady". |
| 4 | A way to reach the node's shell from the machine running the lab | the cluster | The fix happens on the node, not through the API server: `systemctl start kubelet` and `systemctl enable kubelet`. Minikube gives you `minikube ssh -p <profile>`. |
| 5 | A privileged helper pod, or SSH, so the kubelet's state can be read back | the cluster | The grader confirms `systemctl is-active kubelet` and `systemctl is-enabled kubelet` with `kubectl debug node/<node> --image=busybox -- chroot /host ...`. If neither the helper pod nor SSH can run, that specific check is skipped, not failed. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | The broken worker node reports `Ready=True` again | `LabValidate.bash` |
| B | The node reports a `kubeletVersion`, proving a kubelet is reporting in | `LabValidate.bash` |
| C | The kubelet service is **running** on that node (`systemctl is-active kubelet` → `active`) | `LabValidate.bash` |
| D | The kubelet service is **enabled** on that node (`systemctl is-enabled kubelet` → `enabled`) | `LabValidate.bash` |

## Why this pre-state is what it is

A broken cluster is the exam's favourite subject, and this is a broken cluster
with nothing wrong in it. Every object the API server holds is still correct:
the Node object, its labels, its taints, its capacity. What is missing is a
process on one machine.

That is the point. If the pre-state were "the node's spec is wrong", the
answer would be an `kubectl` command. Because the pre-state is "the kubelet is
not running", the answer has to be found and applied on the node itself, and
the candidate has to know that `systemctl` is where that answer lives.

It also explains the *second* half of the task, which is easy to skip. Starting
the kubelet fixes the node; **enabling** it is what stops the same thing
happening again after a reboot, because a service that is merely started is
not necessarily started at boot. The exam asks for both, so the grader asks
for both.

## Gotchas

- **A NotReady node is almost always a kubelet or container-runtime problem,
  not a spec problem.** When a node goes `NotReady`, look at the node's
  processes first — the kubelet and the container runtime (containerd,
  CRI-O, dockershim). A spec problem would show up as `Pending` pods, not as
  a node condition.

- **`kubectl describe node` is where the heartbeat shows up.** The `Status`
  section prints `Last Heartbeat Time`, `Last Transition Time` and the
  `Ready` condition. A kubelet that has stopped leaves a stale heartbeat
  time, and after the node-monitor grace period the `Ready` condition flips
  to `Unknown` (and often the `MemoryPressure`/`DiskPressure` conditions go
  too). `Unknown` is the usual symptom of a dead kubelet; `False` is the
  usual symptom of a node that is up but unhealthy.

- **`systemctl start` is not `systemctl enable`.** `systemctl start kubelet`
  starts it now. `systemctl enable kubelet` makes the operating system start
  it at boot. `systemctl enable --now kubelet` does both. The task asks for
  the node to survive a reboot, so the grader checks `is-enabled` as well as
  `is-active`, and a candidate who only started the service gets half the
  marks.

- **A NotReady node does not go Ready the instant you start the kubelet.**
  The kubelet has to come up, register, and then renew its lease before the
  node's status is updated. Allow a few seconds, and check
  `kubectl get nodes` again rather than assuming the fix failed.

- **The helper pod needs the node's kubelet.** `kubectl debug node/<node>`
  creates a pod pinned to that node, so it is created even while the node is
  NotReady — but the container cannot start without a kubelet on that node to
  run it. In other words, you can use the helper pod to *check* a repaired
  node, but you cannot use it to repair a dead one. That is what SSH (or
  `minikube ssh`, or `docker exec` on a kind node) is for.

- **`chroot /host` is how the helper pod reaches the host.** The pod mounts
  the node's root filesystem at `/host`; `chroot /host systemctl ...` runs
  the *node's* systemd against the *node's* units. Running `systemctl` in the
  container without the chroot would report on the container, not the node.

- **Do not confuse `is-active` with `is-enabled`.** `is-active` answers "is
  it running now" and `is-enabled` answers "will it start at boot". They are
  separate units of state and the grader checks both.

## Environment requirements

- A cluster with a control-plane node and at least one worker node.
- Shell access to the worker node from the machine running the lab:
  `minikube ssh -p <profile>` for minikube, plain `ssh` to the node's
  InternalIP for a normal cluster, or `docker exec <node>` for a kind node.
- The `busybox` image pullable on the cluster, if the helper pod is going to
  be used to read the kubelet's state. Without it, those two checks are
  skipped rather than failed.
- The setup script must run as a user that can stop a system service on the
  node (root on the node, or root-equivalent).
