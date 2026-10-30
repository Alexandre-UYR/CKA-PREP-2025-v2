# x12 — One door open, one door shut: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `netpol` | `LabSetUp.bash` | Both policies and all three Pods live here. The namespace is re-created on every run, so a policy left behind by a previous attempt does not survive. |
| 2 | Namespace `frontend`, labelled `name=frontend` | `LabSetUp.bash` | The client is on the other side of a namespace boundary. The label is there so a `namespaceSelector` has something to match. Every namespace also carries `kubernetes.io/metadata.name`, which is the other way to name it. |
| 3 | Pod `my-httpd`, image `httpd:2.4`, label `app=httpd` | `LabSetUp.bash` | The Pod the first policy selects. It serves on port 80. |
| 4 | Pod `my-proxy`, image `nginx:1.25-alpine`, label `app=proxy` | `LabSetUp.bash` | The Pod the second policy shuts off. It serves on port 80, so a blocked connection is unmistakable. |
| 5 | Pod `my-app`, image `nginx:1.25-alpine`, label `app=myapp` | `LabSetUp.bash` | The Pod that has to be kept away from the proxy. Its image is alpine, so `wget` is available inside it for the probe. |
| 6 | Pod `client`, image `curlimages/curl`, label `httpd-access=true`, in namespace `frontend` | `LabSetUp.bash` | The Pod the first policy has to let in. It is the only Pod in the cluster carrying that label, and it lives in another namespace on purpose. |
| 7 | Services `my-httpd` and `my-proxy`, both on port 80 | `LabSetUp.bash` | So the probes can use a name rather than an address. A Service is not a Pod: a policy selects Pods, and the traffic still has to be allowed on the Pod at the other end. |
| 8 | No NetworkPolicy anywhere | the setup's absence of them | The pre-state is "everything is reachable from everywhere". |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | Two NetworkPolicies in namespace `netpol` | `LabValidate.bash` |
| B | One of them selects `app=httpd` and has an ingress rule whose `from` contains a `podSelector` matching `httpd-access=true` | `LabValidate.bash` |
| C | That policy admits nobody else - no rule with an empty `from`, no empty `namespaceSelector`, no `0.0.0.0/0` | `LabValidate.bash` |
| D | The other one selects `app=proxy` and lists no ingress rule, which is the deny | `LabValidate.bash` |
| E | A Pod labelled `httpd-access=true` reaches `my-httpd` on port 80 with HTTP 200 | `LabValidate.bash` (live) |
| F | `my-app` cannot reach `my-proxy` | `LabValidate.bash` (live) |

## Gotchas

- **A NetworkPolicy that selects a Pod and lists no ingress rules isolates that
  Pod completely.** The `podSelector` alone is the selection, and the absence
  of rules is the deny. Nothing reaches the Pod, from anywhere.

- **A rule with an empty `from` is the opposite of what you want.** An
  ingress rule that lists no `from` at all admits every source in the
  cluster. (A rule whose `from` is an empty *list* is a rule that lets
  nothing in - a different thing, and not the answer either.) The way to
  deny ingress is to have no ingress rules at all.

- **A `podSelector` on its own only matches Pods in the same namespace.** The
  Pod that carries `httpd-access=true` is in `frontend`, and the policy is in
  `netpol`, so the rule needs a `namespaceSelector` as well as the
  `podSelector`. The two go in the same `from` entry:

  ```yaml
  from:
    - namespaceSelector:
        matchLabels:
          name: frontend
      podSelector:
        matchLabels:
          httpd-access: "true"
  ```

- **A policy selects Pods, not Services.** `my-httpd` and `my-proxy` are
  Services, and the traffic ends up at the Pod behind them. Allowing the
  Service is not enough; the Pod has to be allowed.

- **Selecting a Pod in a policy with an ingress rule also isolates that Pod's
  egress.** Once a policy selects a Pod, the only outbound traffic it is
  allowed is what the policy's egress rules say. A policy that selects
  `app=httpd` and says nothing about egress leaves `my-httpd` free to talk
  outwards, but a policy that also lists egress rules needs DNS in them.

- **The label value is the string `true`, not the boolean.** In YAML,
  `httpd-access: true` is a boolean and the API server refuses it as a label
  value. It has to be quoted.

## Environment requirements

- A cluster with at least one node, and registry access for `httpd:2.4`,
  `nginx:1.25-alpine` and `curlimages/curl`.
- **NetworkPolicy is only enforced if the CNI implements it.** The CNI has to
  honour NetworkPolicy objects - Calico, Cilium and Weave Net do, the plain
  bridge CNI that kubeadm installs does not. On a cluster whose CNI ignores
  policies, the negative probe keeps succeeding no matter what the policy
  says, and the validator says so in the failure message rather than
  pretending the policy was wrong.
- The negative probe needs the connection to be dropped or refused, so the
  probe waits for a timeout. That takes a few seconds.
