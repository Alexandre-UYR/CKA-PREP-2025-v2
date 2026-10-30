# Q8 — CNI & Network Policy: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | A running cluster with at least one node | the playground itself | The task is to install a CNI, which means replacing or adding the layer that gives pods an IP address and a route to each other. There has to be a cluster to install it into. |
| 2 | `kubectl` access to that cluster, and permission to install cluster-scoped resources | the playground | The tigera-operator manifest creates CRDs, a namespace and a DaemonSet — all cluster-scoped or privileged. |
| 3 | A CNI already installed | the playground (usually Flannel) | This is what makes the question a *choice* rather than a first install. The candidate is replacing it. |
| 4 | A record of the nodes and the DaemonSets that were running before | `LabSetUp.bash`, into `/tmp/cka-lab/q8.nodes` and `q8.ds.before` | The reset needs to know what it removed so it can tell you what to put back. |
| 5 | Internet access from the machine running `kubectl` | the playground | Both manifests are fetched over HTTPS. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | A CNI installed from a manifest — Calico v3.28.2 via `tigera-operator.yaml` | `LabValidate.bash` (CRD, tigera-operator deployment, calico-node DaemonSet ready on every node) |
| B | Requirement 1: pods can communicate with each other | `LabValidate.bash` (live test between two pods) |
| C | Requirement 2: NetworkPolicy is enforced | `LabValidate.bash` (live test that a deny-all policy blocks traffic) |
| D | Requirement 3: installed from a manifest, not from a package | satisfied by A — both accepted manifests are manifests |

## The key insight this question tests

**Flannel cannot be the answer.** The question lists Flannel *and* Calico as
options, but Flannel has no NetworkPolicy implementation at all — it does not
evaluate policy objects, it just does not implement the API. Requirement 2 rules
it out. The only acceptable choice is Calico.

That is why the validator checks specifically for Calico's CRD
(`crd.projectcalico.org`), the `tigera-operator` deployment and the
`calico-node` DaemonSet, and why it separately *live-tests* that a policy is
actually enforced rather than trusting the presence of the Calico objects.

## Gotchas

- **Installing Calico next to Flannel is normal.** The manifests do not remove
  the old CNI. On the exam environment you install Calico and the nodes end up
  running both, with Calico taking over the pod network. That is acceptable;
  the validator only warns about it.

- **A NetworkPolicy object existing proves nothing.** Plenty of CNIs accept
  policy objects and ignore them. The live test — apply a deny-all policy and
  confirm traffic stops — is what actually grades requirement 2. If the
  negative test fails, the message tells you the policy is wrong *or* the CNI
  is not enforcing policies, and those need to be told apart.

- **Calico takes a while to come up.** After the manifest is applied the
  `calico-node` DaemonSet needs to roll out on every node and the
  `tigera-operator` has to install the custom resources. `kubectl get pods -n
  kube-system` is not ready a few seconds after the apply.

## Environment requirements

- **A disposable cluster.** Swapping the CNI re-writes the networking on every
  node. The `LabReset.bash` for this question removes Calico, which leaves the
  cluster with no working pod network until you reinstall one — the script says
  so when it runs.
- The validator pulls `nginx:alpine` for its connectivity tests, so it needs
  registry access from the cluster and roughly 30 seconds.
- The validator creates and deletes a throwaway namespace, `cka-q8-test`. If it
  is interrupted it may survive; the next run cleans it up first.
