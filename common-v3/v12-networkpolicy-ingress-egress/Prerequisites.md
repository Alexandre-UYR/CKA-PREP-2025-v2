# v12 — Open the door, but only that door: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `pol` | `LabSetUp.bash` | Holds the api, its Service, and the NetworkPolicy the candidate writes. Recreated on every run, so the pre-state is always the same. |
| 2 | Deployment `api`, 1 replica, `nginx:1.25-alpine`, labels `app=api` | `LabSetUp.bash` | The workload the policy selects. The candidate identifies it by label, so the label has to be there to find. |
| 3 | Service `api`, port 80, selector `app=api` | `LabSetUp.bash` | The stable name the probes use: `api.pol.svc.cluster.local`. Without a Service the candidate would have to hunt for a pod IP, which is not a stable thing to grade. |
| 4 | Namespace `client`, labelled `name=client` | `LabSetUp.bash` | The one namespace that is allowed in. The label is what a `namespaceSelector` matches on — namespaces are selected by label, never by name. |
| 5 | Namespace `other`, with **no** label | `LabSetUp.bash` | The namespace that must stay out. It carries no label precisely so that a `namespaceSelector` matching `name=client` cannot pick it up by accident. |
| 6 | A probe pod in `client` and a probe pod in `other` (`curlimages/curl`, running `sleep 3600`) | `LabSetUp.bash` | The candidate needs somewhere to run `curl` from, on both sides of the wall. The validator uses the same two pods to prove the policy works. |
| 7 | No NetworkPolicy anywhere in the cluster | by omission | The pre-state is an open cluster. The isolation the candidate writes is entirely theirs to create — and entirely theirs to get subtly wrong. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | A NetworkPolicy `api` in namespace `pol` | `LabValidate.bash` |
| B | `.spec.podSelector` selects `app=api` | `LabValidate.bash` |
| C | `.spec.policyTypes` includes both `Ingress` and `Egress` | `LabValidate.bash` |
| D | The ingress rule has a `from` entry with a `namespaceSelector` that matches the namespace labelled `name=client` | `LabValidate.bash` |
| E | The ingress rule is restricted to TCP port 80 | `LabValidate.bash` |
| F | The egress rules allow DNS on UDP 53 and on TCP 53 | `LabValidate.bash` |
| G | No unrestricted egress — no `ipBlock: 0.0.0.0/0`, and no empty `to: []` | `LabValidate.bash` |
| H | Live: a pod in `client` gets HTTP 200 from `api.pol.svc.cluster.local` | `LabValidate.bash` |
| I | Live: a pod in `other` does **not** get HTTP 200 from the same URL | `LabValidate.bash` |
| J | Live: a pod in `pol` can still resolve names | `LabValidate.bash` |

## Gotchas

- **A policy that selects a pod and lists an ingress rule also isolates that
  pod's egress.** The isolation is implicit. As soon as the policy selects the
  api pods, all of their outbound traffic is denied, except what the egress
  rules explicitly allow. So the moment the candidate writes the ingress half,
  the api loses DNS and every outbound call — and the policy looks perfectly
  correct when you read it top to bottom. That is the trap: the app breaks
  quietly, and the failure shows up as "the api cannot resolve names" rather
  than as an obvious mistake in the YAML.

- **DNS needs both UDP and TCP 53.** A UDP-only egress rule fails on the
  larger responses that fall back to TCP, and on some resolvers that retry
  over TCP. The grader wants both.

- **`to: []` matches nothing.** An empty destination list is not "anywhere",
  it is "nowhere". The rule reads as though it allows something and silently
  allows nothing. A rule with no `to` at all is "any destination" — which is
  what the DNS rule wants, because the rule is already narrow by port.

- **`ipBlock: 0.0.0.0/0` is "allow everything".** A candidate who writes a
  catch-all egress rule to "make DNS work" has also made the api able to
  reach the whole internet, which is exactly what the task forbids.

- **Namespaces are selected by label, not by name.** `namespaceSelector:
  {matchLabels: {name: client}}` matches the *labelled* namespace `client`.
  The `other` namespace has no label, so it is not matched — and a rule that
  used an empty `namespaceSelector: {}` would match every namespace in the
  cluster, which is the opposite of the task.

- **The order of the checks in the policy does not matter, but the empty
  `from`/`to` does.** An ingress rule with no `from` allows *all* sources;
  an egress rule with no `to` allows *all* destinations. Both are legitimate
  syntax and both are traps in this task.

## Environment requirements

- A cluster with at least one node, and registry access for
  `nginx:1.25-alpine` and `curlimages/curl`.
- **A CNI that enforces NetworkPolicy.** This is the one hard requirement, and
  it is not under the candidate's control. Calico, Cilium, Antrea and
  OpenShift SDN all enforce it; a cluster on plain Flannel, or on the
  `kind` default network, does not. On a cluster whose CNI ignores
  NetworkPolicy, check I can never pass: the pod in `other` still gets HTTP
  200 no matter how correct the policy is. When that happens the failure
  message says so explicitly — **either the policy is wrong, or this cluster's
  CNI does not enforce NetworkPolicy** — so the candidate is not left chasing
  a bug in their YAML. Check the CNI before treating the failure as the
  candidate's.
- The remaining checks (A through H, and J) are read from the API server and
  pass on any cluster.
