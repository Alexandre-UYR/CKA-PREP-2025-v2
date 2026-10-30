# v6 — Give each pod its own identity and its own disk: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `stateful` | `LabSetUp.bash` | The Service, the workload and the StatefulSet all live here, and the task names the namespace. |
| 2 | Service `web-headless`, `clusterIP: None`, selector `app=web`, port 80 | `LabSetUp.bash` | A headless Service is the thing that issues per-pod DNS names. The StatefulSet's `serviceName` has to point at it, and a Service with a cluster IP cannot give per-pod names. |
| 3 | Deployment `web`, 1 replica, `nginx:1.25`, labels `app=web` | `LabSetUp.bash` | The workload the candidate has to turn into a StatefulSet. It exists so the task is a conversion, not a build from nothing. |
| 4 | The Deployment uses the same labels as the headless Service's selector | `LabSetUp.bash` | The inconsistency the candidate has to resolve: once a StatefulSet owns `app=web`, the Deployment's ReplicaSet and the StatefulSet are competing for the same pods, so the Deployment has to go. |
| 5 | The cluster's **default StorageClass** | The cluster | The claim template has to name a StorageClass that exists, and the task asks for the default one. The validator looks the default up live, so it is correct whatever the cluster calls it. |
| 6 | A StorageClass that can actually provision (`WaitForFirstConsumer` or `Immediate`) | The cluster | The three claims have to reach `Bound`, not sit in `Pending`. Without a provisioner the task has no observable end state. |
| 7 | The Deployment's pod is running | `LabSetUp.bash` waits for it | The pre-state has to be the plain workload it claims to be. The setup waits for one ready replica and warns if it has not arrived. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | A StatefulSet `web` in namespace `stateful` | `LabValidate.bash` |
| B | `.spec.serviceName` is `web-headless` | `LabValidate.bash` |
| C | `.spec.replicas` is 3 | `LabValidate.bash` |
| D | `.spec.volumeClaimTemplates` has exactly one entry | `LabValidate.bash` |
| E | That entry requests 1Gi and uses the `ReadWriteOnce` access mode | `LabValidate.bash` |
| F | That entry's `storageClassName` is the cluster's default StorageClass | `LabValidate.bash` |
| G | Pods `web-0`, `web-1` and `web-2` exist and are Ready | `LabValidate.bash` |
| H | Each pod has its own claim, and each claim is `Bound` — three distinct claims | `LabValidate.bash` |
| I | The Service `web-headless` still has `clusterIP: None` | `LabValidate.bash` |

## Gotchas

- **A StatefulSet gives each pod a stable identity and its own storage.** The
  pod's DNS name comes from the governing headless Service, which is why
  `serviceName` points at `web-headless` and the Service has no cluster IP.
  The name is `<podName>.<serviceName>`: `web-0.web-headless`, and so on.

- **`volumeClaimTemplates` are templates, not claims.** The StatefulSet
  controller creates one PVC per pod, from the template, named
  `<claimTemplateName>-<statefulSetName>-<ordinal>` — `web-web-0`,
  `web-web-1`, `web-web-2` if the template is called `web`. The template name
  is the candidate's choice, so the validator finds the claims through the
  pods' volumes rather than by name.

- **A claim template only does anything if the Pod actually mounts it.** The
  claim has to appear in `volumeClaimTemplates` *and* the Pod template has to
  have a matching `volumeMounts` entry, or the PVC is created but never
  attached.

- **The Deployment and the StatefulSet cannot both own `app=web`.** Two
  controllers with the same selector in the same namespace fight over the
  same pods. Delete the Deployment before creating the StatefulSet.

- **`serviceName` does not create the Service.** It only names the one that
  already exists. If the candidate points `serviceName` at something that is
  not headless, the pods come up but the DNS names do not.

- **`readinessProbe` is not needed** for the pods to be Ready. A Pod with no
  probe is Ready as soon as its container is running.

- **The claims take a moment to bind.** With `WaitForFirstConsumer` the PVC
  stays `Pending` until the Pod is scheduled. The validator waits for the
  pods to be Ready before it grades the claims.

- **A PersistentVolume with the `Retain` reclaim policy survives its
  namespace.** That is why the reset script deletes the PVs bound into
  namespace `stateful` as well as the namespace itself.

## Environment requirements

- A cluster with a **default StorageClass** and a provisioner behind it, so
  that three 1Gi claims can be bound. The default is looked up with:
  `kubectl get storageclass -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}'`
- Registry access for `nginx:1.25`.
- No special components: a StatefulSet, a headless Service and dynamic
  provisioning are all standard.
