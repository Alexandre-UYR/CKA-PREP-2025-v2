# Q9 — cri-dockerd: prerequisite inventory

This is a **node-level** question. Nothing here goes through the API server: the
grader inspects the machine it is running on.

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | The package file `/root/cri-dockerd.deb` | `LabSetUp.bash`, downloaded from the Mirakis release | The task says to install *that* package. Downloading it is the exam environment's job; installing and configuring it is the candidate's. |
| 2 | A machine running systemd | the node itself | The task enables and starts `cri-docker.service` — a systemd unit that ships with the package. Without systemd there is nothing to enable. |
| 3 | Root, or a user with passwordless `sudo` | the node itself | `dpkg -i`, `systemctl enable`, writing to `/etc/sysctl.d/` and changing sysctls all need it. |
| 4 | A kernel that exposes `net.bridge.bridge-nf-call-iptables` and `net.netfilter.nf_conntrack_max` | the node's kernel | `bridge-nf-call-iptables` lives in the `br_netfilter` module and `nf_conntrack_max` in `nf_conntrack`. Both are normally present on a Kubernetes node; if they are not, the sysctl reads fail and the validator says so rather than reporting a wrong value. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | The `cri-dockerd` package installed (`dpkg -i`) | `LabValidate.bash` |
| B | `cri-docker.service` enabled | `LabValidate.bash` |
| C | `cri-docker.service` running | `LabValidate.bash` |
| D | `net.bridge.bridge-nf-call-iptables = 1` | `LabValidate.bash` (live `sysctl -n`) |
| E | `net.ipv6.conf.all.forwarding = 1` | `LabValidate.bash` (live `sysctl -n`) |
| F | `net.ipv4.ip_forward = 1` | `LabValidate.bash` (live `sysctl -n`) |
| G | `net.netfilter.nf_conntrack_max = 131072` | `LabValidate.bash` (live `sysctl -n`) |
| H | The four settings persisted so they survive a reboot (`/etc/sysctl.d/kube.conf`) | `LabValidate.bash` (file contents) |

## Gotchas

- **Setting a sysctl is not the same as persisting it.** `sysctl -w
  net.ipv4.ip_forward=1` changes the running kernel only. It is lost on reboot
  unless it is written to a file under `/etc/sysctl.d/`. The task's four values
  are exactly the ones the kubeadm bootstrap writes, and the validator checks
  both the live value *and* the persisted file, because a candidate who only
  ran `sysctl -w` has done half the task.

- **The keys are not all under the same prefix.** Two of them are under
  `net.ipv4` / `net.ipv6`, one under `net.bridge` and one under
  `net.netfilter`. A single `sysctl -w` call takes one key at a time; four
  calls, or a file plus `sysctl --system`.

- **`net.netfilter.nf_conntrack_max` is a large integer.** `131072`, not
  `131k` and not `128Ki`. It is a plain count of connection-tracking entries,
  not a byte size.

- **`sysctl --system` reloads every file in `/etc/sysctl.d/`,** not just the one
  you wrote. On a node that already has Kubernetes sysctls, that is usually
  harmless, but it is worth knowing before you run it.

- **The service name is `cri-docker.service`,** with a hyphen, while the
  package is `cri-dockerd`. `systemctl enable cri-dockerd` fails.

## Environment requirements

- Root or passwordless `sudo` on the node.
- `systemd` and `dpkg` — this is a Debian-family node. The package in the
  pre-state is the `debian-bullseye` build.
- The validator runs on the node, not through `kubectl`. Run it in the same
  shell as the setup, on the node itself.
