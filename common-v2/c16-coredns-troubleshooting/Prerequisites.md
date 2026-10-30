# c16 — Cluster DNS has stopped working: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `dns` | `LabSetUp.bash` | The namespace the task says the pods live in, and the namespace the verification pod is run from. |
| 2 | A healthy CoreDNS in `kube-system` (Deployment `coredns` plus its ConfigMap `coredns`) | the cluster itself | This is the component that serves cluster service names. The question breaks it on purpose, so it has to be there to be broken. |
| 3 | A Corefile that contains the `kubernetes` plugin | the cluster itself | The plugin that answers queries for names inside `cluster.local`. Renaming it is the break. |
| 4 | A working kubelet and scheduler, so the CoreDNS pods can be recreated | the cluster itself | The fix requires new CoreDNS pods. |
| 5 | Registry access for `busybox:1.36` | the environment | The verification pod uses that image. |
| 6 | A copy of the original ConfigMap and Corefile under `/tmp/cka-lab` | `LabSetUp.bash` | The reset needs it to put the cluster back the way it was. The setup restores that copy before it breaks anything again, so running the setup twice is safe. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | A Corefile that names the `kubernetes` plugin again (and no longer names the broken plugin) | `LabValidate.bash` |
| B | A CoreDNS Deployment with at least 1 ready replica | `LabValidate.bash` |
| C | Proof that a pod can resolve `kubernetes.default.svc.cluster.local` | `LabValidate.bash` (live probe) |

## Gotchas

- **CoreDNS reads its Corefile at start-up.** The ConfigMap is mounted as a
  file, and CoreDNS parses that file when the process starts. Editing the
  ConfigMap does not change the running process, so the Deployment has to be
  restarted for a corrected Corefile to take effect:

  ```
  kubectl -n kube-system rollout restart deploy/coredns
  ```

  This is the trap in the question. A candidate who edits the ConfigMap,
  sees the object is correct, and stops there has not finished.

- **A crash-looping pod takes its time to come back.** After a fix the pod is
  still in CrashLoopBackOff, and the backoff grows to minutes. `kubectl rollout
  status` after a restart gives a fresh pod immediately, which is why the
  restart is part of the answer and not just good practice.

- **The `kubernetes` plugin serves cluster service names.** `kubernetes.default.svc.cluster.local`
  is answered by the `kubernetes` plugin, which knows the API server and the
  zones it is authoritative for. External names (`example.com`) are not: they
  go through `forward . /etc/resolv.conf`, which hands them to the node's
  resolver. Renaming the `kubernetes` plugin therefore breaks only the
  cluster names, which is exactly what the task reports.

- **The Corefile is a file inside the ConfigMap.** It lives under the `Corefile`
  key, not at the top level of the ConfigMap:

  ```
  kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}'
  ```

  and it is edited with `kubectl edit configmap coredns`, or replaced with a
  `kubectl create configmap coredns --from-file=Corefile=... --dry-run=client -o yaml | kubectl apply -f -`.

- **The pods say what is wrong.** `kubectl -n kube-system logs deploy/coredns`
  prints the parse error, with the plugin name it could not read. That log
  line is the shortest path from "DNS is broken" to "this one word in the
  Corefile is wrong".

- **Do not restart the nodes.** The task says so, and it is the right advice:
  a broken ConfigMap is fixed by fixing the ConfigMap. Rebooting a node would
  not help, and it is the kind of reflex the exam is testing.

## Environment requirements

- A cluster with CoreDNS installed in `kube-system` (kubeadm, minikube, kind
  and most cloud clusters all have it) and at least one node.
- The CoreDNS Deployment must be named `coredns` and its ConfigMap `coredns`,
  which is the kubeadm default.
- Registry access for `busybox:1.36`.
- The setup needs permission to read and write the CoreDNS ConfigMap and to
  restart the CoreDNS Deployment. It works on a cluster where the current user
  is a cluster administrator.
- The setup restarts the CoreDNS Deployment on purpose. Cluster DNS is
  therefore unavailable for a few seconds while the question's environment is
  being prepared, and the CoreDNS pods stay in CrashLoopBackOff until the
  candidate fixes the Corefile. Nothing else in the cluster needs CoreDNS to
  work while the question is open.
