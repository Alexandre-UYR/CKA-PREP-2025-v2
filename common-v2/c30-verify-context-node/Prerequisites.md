# c30 — Know where you are before you act: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | A kubectl context that is set and points at a reachable cluster | the cluster and the kubeconfig | The task asks which context you are on, so there has to be one, and `kubectl version` has to work for it to be the right answer rather than a stale one. |
| 2 | A shell on the machine you will work from | the environment | The hostname is a property of the machine, not the cluster. It is not the same as the control-plane node's name. |
| 3 | The current context and hostname recorded | `LabSetUp.bash`, into `/tmp/cka-lab/c30.context` and `c30.host` | So the candidate can see the starting point and check themselves, and so the reset knows what to clean up. |

The setup **creates nothing and changes nothing**. It only reads.

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | `/root/current-context.txt` exists and holds exactly the current context name | `LabValidate.bash` |
| B | `/root/current-node.txt` exists and holds exactly the machine's hostname | `LabValidate.bash` |
| C | The control plane's version is reachable with `kubectl version` | `LabValidate.bash` |

## Why this question exists

It is deliberately the easiest one in the set, and it is still worth doing. The
exam says each task may begin in a fresh session, potentially on a different
node, and **bash aliases and shell functions do not survive a new session**. A
candidate who set up `alias k=kubectl` in a previous session, or who assumed
they are still on the control plane, will lose marks on a task for reasons that
have nothing to do with Kubernetes.

Two commands settle it:

```bash
kubectl config current-context
hostname
```

If the context is not the one you expect, `kubectl config use-context` fixes it.
If the hostname is a worker rather than the control plane, you know that the
node-level parts of the task have to be done over there.

## Gotchas

- **The hostname is not the node name in the cluster.** `hostname` on the
  control-plane node is often the machine's hostname, which may not match
  `kubectl get nodes`' name for that node (a kind control plane is called
  `kind-control-plane`, a minikube one `minikube`, but a cloud VM's hostname
  can be something else entirely). The task asks for the hostname, not the
  node's Kubernetes name.

- **`kubectl version` may need a `--short` on older clients** and prints
  client and server versions. Either form satisfies the task.

- **A context can be set and still be wrong.** `kubectl config current-context`
  prints the name of the current context, not proof that it points where you
  think. `kubectl cluster-info` confirms where it actually points.

- **Do not put anything else in the files.** One value per file, nothing else on
  the line.

## Environment requirements

- A kubeconfig with a current context.
- Read access to `/root` for the validator, or run the validator as root.
- The hostname command must exist (`hostname` is in coreutils and in the base
  image of every node).
