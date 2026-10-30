# x8 — Cluster names work, the internet does not: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `dns` | `LabSetUp.bash` | The namespace the task names, and the namespace the verification pods are run from. |
| 2 | A healthy CoreDNS in `kube-system` — the Deployment and its ConfigMap | the cluster itself | This is the component that serves both kinds of name. The question breaks it on purpose, so it has to be there to be broken. |
| 3 | A Corefile with a `kubernetes` plugin and a `forward` directive | the cluster itself | The two plugins whose difference is the whole question. The `forward` directive is what the setup removes. |
| 4 | The original Corefile saved at `/tmp/cka-lab/x8.corefile` | `LabSetUp.bash` | The reset needs it to put the cluster back the way it was. The setup restores that copy BEFORE it breaks anything again, so running the setup twice is safe. |
| 5 | The setup waits for CoreDNS to come back up after the break | `LabSetUp.bash` | The pre-state has to BE the broken state. If CoreDNS were left crash-looping, the symptom would be "no DNS at all" rather than the specific half-working DNS the task describes. |
| 6 | The setup probes the cluster and the outside world to confirm the symptom | `LabSetUp.bash` | It checks that a cluster name resolves and that an external name does not, so that nobody is handed a pre-state that is not broken in the way the task says. |
| 7 | Registry access for `busybox:1.36` | the environment | The verification pods use that image. |
| 8 | A working kubelet and scheduler, so the CoreDNS pods can be recreated | the cluster itself | The fix requires new CoreDNS pods. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | The CoreDNS ConfigMap's Corefile contains a `forward` directive pointing at a resolver | `LabValidate.bash` — the Corefile is read out of the ConfigMap |
| B | The CoreDNS Deployment has at least 1 ready replica | `LabValidate.bash` |
| C | CoreDNS was restarted after the ConfigMap was changed | `LabValidate.bash` — the pod's start time is compared with the ConfigMap's last write time, and the `kubectl.kubernetes.io/restartedAt` annotation is accepted as well |
| D | A pod resolves `kubernetes.default.svc.cluster.local` | `LabValidate.bash` (live check) |
| E | A pod resolves `example.com` | `LabValidate.bash` (live check) — skipped, with a reason, on a cluster whose upstream resolver cannot reach the outside either |

## Gotchas

- **The `kubernetes` plugin serves the names inside the cluster.** It knows
  the API server, and it is authoritative for `cluster.local` and for the
  in-addr.arpa zones. `kubernetes.default.svc.cluster.local` is answered by
  it, and by nothing else.

- **The `forward` plugin sends everything else to the node's resolver.**
  `forward . /etc/resolv.conf` hands any name the `kubernetes` plugin does
  not know to the resolver in CoreDNS's own `/etc/resolv.conf` — which, in a
  kubeadm cluster, is the node's own resolver. Remove that one line and the
  `kubernetes` plugin keeps working perfectly, while every external name
  fails. That is why the symptom is so specific, and why "DNS is broken" is
  the wrong diagnosis.

- **The `forward` directive is a block, not a line.** In the stock Corefile
  it reads:

  ```
      forward . /etc/resolv.conf {
         max_concurrent 1000
      }
  ```

  Deleting only the `forward . /etc/resolv.conf` line leaves the `{` and the
  `}` behind, and CoreDNS then fails to parse its own configuration and
  crash-loops. The whole directive, block included, has to go — or be put
  back.

- **CoreDNS reads its Corefile at start-up.** The Corefile is a file in a
  ConfigMap, mounted into the pod, and CoreDNS parses it when the process
  starts. Editing the ConfigMap does not change the running process, so the
  Deployment has to be restarted:

  ```
  kubectl -n kube-system rollout restart deploy/coredns
  ```

  This is the trap in the question. A candidate who edits the ConfigMap,
  sees that the object now says the right thing, and stops there has not
  finished: the pods are still running the old configuration.

- **The pod's start time is the evidence.** `kubectl -n kube-system get pods
  -l k8s-app=kube-dns -o custom-columns=NAME:.metadata.name,START:.status.startTime`
  shows when the running CoreDNS actually started. If that is older than
  the ConfigMap's last change, the pods have not picked the new Corefile
  up.

- **Do not restart the nodes.** The task says so, and it is the right advice:
  a Corefile is fixed by fixing the Corefile.

- **A crash-looping pod takes its time to come back.** After a fix the pod
  is still backing off, and the backoff grows to minutes. `kubectl rollout
  status` after the restart gives a fresh pod straight away.

- **External resolution can fail for a reason that is not the cluster's
  fault.** If the node's own resolver cannot reach the internet, no amount
  of CoreDNS fixing will make `example.com` resolve. The grader compares
  the result with what a pod that uses the node's resolver directly can do,
  and skips the check when the outside world is simply not reachable from
  here.

## Environment requirements

- A cluster with CoreDNS in `kube-system` (kubeadm, kind, minikube and most
  cloud clusters all have it) and at least one node.
- The CoreDNS ConfigMap and Deployment are found by name (`coredns`) or by
  the `k8s-app=kube-dns` label, so a cluster that names them differently
  still works.
- Permission to edit the CoreDNS ConfigMap and to restart the CoreDNS
  Deployment — in practice, cluster-admin.
- Registry access for `busybox:1.36`.
- The setup restarts the CoreDNS Deployment on purpose. Cluster DNS is
  unavailable for a few seconds while the environment is being prepared, and
  external names stay broken until the candidate puts the `forward`
  directive back.
