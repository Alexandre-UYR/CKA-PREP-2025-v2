# Q13 — Network Policy: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `frontend` | `LabSetUp.bash` | One half of the pair the question talks about. |
| 2 | Namespace `backend` | `LabSetUp.bash` | The other half. The NetworkPolicy you apply has to live in `backend`, because a NetworkPolicy only ever restricts traffic **into** the pods it selects, in the namespace it lives in. |
| 3 | **Label `name=frontend` on the `frontend` namespace** | `LabSetUp.bash` (`kubectl label namespace frontend name=frontend --overwrite`) | This is the one that is easy to miss. `policy-z` allows the frontend in with a `namespaceSelector: {matchLabels: {name: frontend}}` — a selector over **namespace labels**. Without the label on the namespace, `policy-z` matches nothing, the frontend is locked out, and the "correct" answer does not work. The exam environment provides this label; the lab has to as well. |
| 4 | Deployment `backend-deployment` (nginx, 1 replica, labels `app=backend`, container port 80) in `backend` | `LabSetUp.bash` | The workload the policy protects. Its pod labels are what `podSelector: {matchLabels: {app: backend}}` selects — if the labels were different, the policy would protect nothing. |
| 5 | Service `backend-service` (ClusterIP, port 80 -> targetPort 80) in `backend` | `LabSetUp.bash` | The stable DNS name the frontend pod uses to reach the backend. A test that curled the pod IP would not be testing the policy the way the question intends. |
| 6 | Deployment `frontend-deployment` (image `curlimages/curl`, command `["sleep","3600"]`, labels `app=frontend`) in `frontend` | `LabSetUp.bash` | The client side of the conversation. `sleep 3600` keeps the pod alive so something can be run inside it; `curlimages/curl` is there so the image already in the cluster is the one the connectivity probes use. |
| 7 | Three candidate policies in `/root/network-policies/network-policy-1.yaml` (policy-x), `-2.yaml` (policy-y) and `-3.yaml` (policy-z) | `LabSetUp.bash` | The material the question is actually about. You are given three policies and have to work out which one is the least permissive that still does the job. |
| 8 | Pod labels `app=frontend` on the frontend pods | `LabSetUp.bash` | `policy-z` allows the frontend in twice: once by namespace (`name=frontend`) and once by `podSelector: {matchLabels: {app: frontend}}`. The pod-label half of that only works if the pods carry the label. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | A NetworkPolicy applied in namespace `backend` | `LabValidate.bash` |
| B | It must be `policy-z` — the least permissive of the three files | `LabValidate.bash` (name + full spec compared against `network-policy-3.yaml`) |
| C | `spec.podSelector` selects `app=backend` | `LabValidate.bash` |
| D | `spec.policyTypes` includes `Ingress` | `LabValidate.bash` |
| E | No `ipBlock` in the ingress rules (that would be policy-y) | `LabValidate.bash` |
| F | No unrestricted / empty ingress rule (that would be policy-x) | `LabValidate.bash` |
| G | The `frontend` namespace is labelled `name=frontend` | `LabValidate.bash` (this is a prerequisite, but a candidate who deleted the label breaks the answer, so it is checked) |
| H | A pod in `frontend` reaches `backend-service:80` and gets HTTP 200 | `LabValidate.bash` (live test) |
| I | A pod **outside** `frontend` does **not** reach `backend-service:80` | `LabValidate.bash` (live negative test) |

## Gotchas

- **A NetworkPolicy is additive within a namespace and it is a *deny* model.**
  Once any policy selects a pod, that pod becomes "isolated" for the given
  direction, and traffic is allowed only by the rules of the policies that select
  it. `policy-x` has `podSelector: {}` (every pod) and `ingress: [{}]` (one
  empty rule = allow everything), which is the "allow all" policy.

- **The `from:` list is an OR, not an AND.** `policy-z` has two entries under
  `from:`: a `namespaceSelector` for `name=frontend` **and** a `podSelector` for
  `app=frontend`. That means traffic is allowed if *either* matches. The
  `podSelector` entry with no `namespaceSelector` next to it selects pods in the
  **policy's own namespace** (`backend`), so policy-z would also let a pod
  labelled `app=frontend` in `backend` in. There is none, so it does not matter
  here — but it is exactly why policy-z is "least permissive *for this pair*"
  and not "least permissive in the abstract".

- **`policy-y` looks almost right.** It has the same `namespaceSelector`, but it
  *also* has an `ipBlock: {cidr: 172.16.0.0/16}`, which opens the backend to
  every source IP in that range. That is the whole difference between "least
  permissive that works" and "policy-y".

- **The namespace needs the label, not the pods.** `namespaceSelector` selects
  *namespaces* by their labels; `podSelector` selects *pods* by theirs. They are
  different things and confusing them is the classic mistake. The label that
  matters here is `name=frontend` on the **namespace object**.

- **The policy does not have to name the frontend namespace literally in the
  source**, but it has to match it somehow. The three given files all use
  `name: frontend`.

- **`policyTypes` must include `Ingress`.** If you write `policyTypes: [Egress]`
  (or leave it out with no `egress` rules and no `ingress` rules), you have not
  written the policy the question asks for.

- **A policy that is correct on paper can still be useless.** If the CNI does
  not implement NetworkPolicy, every policy is accepted by the API server and
  then ignored by the network. Both live tests in the validator fail in that
  case, and the failure message says so explicitly, so you do not spend an hour
  rewriting a policy that was never going to be enforced.

## Environment requirements

- **A CNI that enforces NetworkPolicy.** This is the hard requirement. Calico,
  Cilium, Antrea and Weave all enforce it; **Flannel does not** (unless you have
  installed flannel with its policy controller). If the cluster runs Flannel,
  the negative test cannot pass no matter what you apply, and the validator
  says "the policy is wrong, OR this cluster's CNI does not enforce
  NetworkPolicy" when it fails.
- **Root, or a user who can read `/root/network-policies`.** The setup writes the
  three candidate files there and the validator compares the applied policy
  against `network-policy-3.yaml`; if the file cannot be read, that one
  comparison prints a `SKIP` line instead of failing.
- Permission to create NetworkPolicies in `backend`, and to create and delete
  throwaway pods in `frontend` and `default` (the validator runs its connectivity
  probes there).
- Outbound access to a container registry, so `curlimages/curl` can be pulled.
- The `default` namespace must exist and must be usable for the negative probe
  (it is the standard namespace, and it is not labelled `name=frontend`, so it is
  a valid "somewhere else" to test from).
