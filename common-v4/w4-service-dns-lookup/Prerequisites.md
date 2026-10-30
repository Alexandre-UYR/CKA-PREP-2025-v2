# w4 — The name that does not resolve: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `dns-demo` | `LabSetUp.bash` | Every object in the question lives here, and the task names the namespace. The setup deletes and re-creates the namespace on each run, so a leftover answer file or pod from an earlier attempt cannot pass the validation. |
| 2 | Pod `redis` — redis:7, labels `app=redis`, container port 11211 | `LabSetUp.bash` | The workload behind the Service, and one of the two addresses the candidate has to find. It has to be Running, or there is no Pod IP to write down. |
| 3 | Service `redis-svc` — ClusterIP, port 11211 → targetPort 11211, selector `app=redis-v2` | `LabSetUp.bash` | The broken half. The selector matches no pod, so the Service has no endpoints — but it still has a ClusterIP, and its name still resolves. |
| 4 | Pod `looker` — busybox:1.28, command `sleep 10000` | `LabSetUp.bash` | The candidate needs somewhere to run `nslookup` from, and the live check in the validator runs `nslookup` in it. busybox ships the `nslookup` applet, so no extra tooling is needed. |
| 5 | The setup waits for the `redis` and `looker` pods to be Running, and for the Service to have no endpoints | `LabSetUp.bash` | The Pod has to have an IP before it can be written down, and the Service has to be broken before the task starts. |
| 6 | CoreDNS running in the `kube-system` namespace | the cluster | The Service name is resolved by CoreDNS, not by the Service object. Without CoreDNS the `nslookup` cannot answer and the task cannot be done. |
| 7 | A writable `/root` on the machine running `kubectl` | the environment | The answer is a file on disk. If `/root` is not writable the candidate cannot produce an answer at all. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | Service `redis-svc` repaired: a selector that matches the pods' labels | `LabValidate.bash` — the Service's selector is compared with the `redis` pod's labels |
| B | The Service has at least one endpoint address | `LabValidate.bash` — the endpoints are counted after a wait, because the endpoints controller reacts asynchronously |
| C | A live `nslookup redis-svc` from the `looker` pod that returns the Service's ClusterIP | `LabValidate.bash` — `kubectl exec` runs `nslookup` in the `looker` pod and the output is compared with the Service's live ClusterIP |
| D | `/root/q5.txt` holding the Service's ClusterIP and the `redis` pod's IP, one per line | `LabValidate.bash` — the file exists, is not empty, has two lines, and contains both addresses as they are live at grading time |

## Gotchas

- **A Service's name resolves to its ClusterIP, and that has nothing to do with
  the selector.** CoreDNS answers `redis-svc` from the Service object, so the
  name resolves whether or not the Service points at anything. That is why the
  name resolving is not the same as the Service working — and why `nslookup`
  succeeds both before and after the fix. The proof that the Service works is
  the endpoints, not the DNS answer.

- **The fix is the selector, and the selector is `app=redis`.** The Service
  asks for `app=redis-v2`; the pod is labelled `app=redis`. Nothing matches,
  so the endpoints are empty.

- **`nslookup` returns more than one address, and the grader compares
  numbers.** The output holds the DNS server's own address as well as the
  answer. The answer has to be the Service's ClusterIP for `redis-svc` and
  the Pod's own IP for `redis` — read them off the live objects and compare,
  rather than trusting the order of the lines.

- **The Pod's address is the Pod IP, not a DNS name.** `redis` the Pod is
  reached by its IP, or by the headless Service name if there were one; there
  is no Service for the Pod here, so it is the IP in `.status.podIP`.

- **The file has two lines, one address each.** Both the Service ClusterIP and
  the Pod IP have to be in it, and the grader checks the number of lines as
  well as the contents. A file with the two addresses on one line, or with
  the `nslookup` output pasted in wholesale, is not what the task asked for.

- **The Pods and the Service live in the same namespace, so a short name
  works.** `redis-svc` resolves to `redis-svc.dns-demo.svc.cluster.local`.
  From another namespace the short name would not, and you would need the
  fully qualified name.

- **`busybox` has `nslookup`; it does not have `dig`.** If the candidate
  reaches for `dig` or `host`, the answer comes back as "not found" and looks
  like a DNS problem that is not there.

## Environment requirements

- A cluster with at least one node, and registry access for `redis:7` and
  `busybox:1.28`.
- CoreDNS running and healthy in `kube-system` — every cluster has it by
  default, and this task cannot be done without it.
- The `looker` pod runs `sleep 10000`, so it stays up for about 2 hours and
  45 minutes. After that it has finished, and a new busybox pod is needed to
  run `nslookup` from.
- Write access to `/root` for the candidate and for the validator.
