# c14 — Allow ingress from one namespace only: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `netpol` | `LabSetUp.bash` | The policy and the workload it protects live here. |
| 2 | Namespace `frontend` | `LabSetUp.bash` | The one namespace whose traffic must reach the `api` pods. |
| 3 | Namespace `other` | `LabSetUp.bash` | The namespace that must be denied. The negative test needs a client on the wrong side of the policy. |
| 4 | Label `name=frontend` on namespace `frontend` | `LabSetUp.bash` | A `namespaceSelector` can only pick namespaces out by their labels. This is the label the policy has to match, and the only thing that distinguishes `frontend` from `other`. |
| 5 | Deployment `api` (nginx, labels `app=api`) in `netpol` | `LabSetUp.bash` | The pods the policy selects. A policy with no `podSelector` would apply to everything in the namespace, so the selector has to name this workload. |
| 6 | Service `api` on port 80 in `netpol` | `LabSetUp.bash` | Gives the policy a stable name to test against: `api.netpol.svc.cluster.local`. Traffic to a Service is forwarded to the pod's port, which is where the policy is enforced. |
| 7 | Deployment `tester` (image `curlimages/curl`, command `sleep 3600`) in `frontend` and in `other` | `LabSetUp.bash` | Somewhere to run the probe from, on both sides of the policy. |
| 8 | A cluster whose CNI implements NetworkPolicy | the cluster itself | A NetworkPolicy is only enforced by the CNI. Without a policy-aware CNI the object exists and nothing happens. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | A NetworkPolicy `allow-frontend` in namespace `netpol` | `LabValidate.bash` |
| B | A `podSelector` that selects the `api` pods | `LabValidate.bash` |
| C | `policyTypes` including `Ingress` | `LabValidate.bash` |
| D | An ingress rule whose `from` carries a `namespaceSelector` matching the label `name: frontend` | `LabValidate.bash` |
| E | That rule restricted to TCP port 80 | `LabValidate.bash` |
| F | No rule that allows every source (no empty `from`, no empty `ingress: [{}]`) and no `ipBlock` | `LabValidate.bash` |
| G | Proof that traffic from `frontend` still works (HTTP 200) | `LabValidate.bash` (live probe) |
| H | Proof that traffic from `other` is blocked | `LabValidate.bash` (live probe) |

## Gotchas

- **A NetworkPolicy is an allow-list.** Once a policy selects a pod, that pod is
  isolated for ingress: traffic that no rule allows is dropped, it is not
  forwarded. You do not need a second "deny" rule for the other namespace.
  Writing one is not wrong, but a policy that denies `other` and allows
  everything else is a different answer from the one the task asks for.

- **A namespaceSelector selects namespaces, not pods.** To allow pods in
  `frontend`, the rule needs `namespaceSelector` with `matchLabels:
  {name: frontend}`. A `podSelector` inside `from` would select pods in the
  *policy's own* namespace, which is `netpol` - not `frontend`.

- **An empty `from` allows every source.** The rule
  `ingress: [{ports: [{port: 80}]}]` has no `from`, which means "from
  anywhere". That is the classic way to write a NetworkPolicy that looks
  restrictive and is not. The same applies to `ingress: [{}]`.

- **The port in `ports` is the port on the pod.** `port: 80` in the ingress
  rule is matched against the destination port of the traffic after the
  Service has been translated, so it lines up with the container port 80.

- **`ipBlock` is not a namespace selector.** `ipBlock` selects by CIDR range,
  which does not survive a pod IP changing and does not express "the frontend
  namespace" at all.

- **`policyTypes` defaults.** If you write only `ingress` rules and leave
  `policyTypes` out, Kubernetes defaults it to `[Ingress]`. Writing it
  explicitly is still better practice, and the grader accepts the default.

- **NetworkPolicy is namespace-scoped.** The policy has to be created in
  `netpol`, in the namespace of the pods it protects - not in the namespace
  of the clients.

## Environment requirements

- A cluster with at least one node and a working CNI.
- **The CNI must implement NetworkPolicy.** This is the one environmental
  caveat that matters here. Calico, Cilium and Antrea enforce policies;
  plain `kindnet` and the default `docker` bridge network do not. On a cluster
  whose CNI ignores policies, the policy object is created and accepted by the
  API server, but the denied probe still answers HTTP 200. When that happens
  the failure is the cluster's limitation, not a wrong answer - the grader
  says so in the failure message.
- Registry access for `nginx` and `curlimages/curl`.
- Cluster DNS working, because the probes resolve `api.netpol.svc.cluster.local`
  rather than using the Service's cluster IP.
- A free cluster port range for any NodePort the candidate creates while
  experimenting.
