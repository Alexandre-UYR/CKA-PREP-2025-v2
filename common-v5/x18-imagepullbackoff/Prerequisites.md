# x18 — The tag that does not exist: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `reg` | `LabSetUp.bash` | The Pod and the ConfigMap both live here, and the task names the namespace. The setup deletes and re-creates the namespace on each run, so a Pod left over from an earlier attempt cannot answer the validation. |
| 2 | ConfigMap `image-tags`, data `nginx: "1.25 1.26"` | `LabSetUp.bash` | The source of truth for which tags exist. One key per image; the value is that image's space-separated list of tags. The candidate is pointed here, and the grader looks the Pod's tag up in THIS data rather than against a fixed list, so the answer follows whatever the ConfigMap says. |
| 3 | Pod `app`, image `nginx:1.99`, command `sleep 10000` | `LabSetUp.bash` | The workload under repair. `1.99` is not in the ConfigMap's list and is not a tag that exists in the registry, so the kubelet cannot pull it and the Pod waits. |
| 4 | A copy of the ConfigMap's data, taken at setup, in `/tmp/cka-lab/x18.cm.data` | `LabSetUp.bash` | The task forbids changing the ConfigMap. The grader compares the live data with this copy. |
| 5 | The Pod to have actually failed to pull | `LabSetUp.bash` polls for the waiting reason | The pre-state has to BE the broken state. The setup waits for `ImagePullBackOff` and warns if it never appeared. |
| 6 | Registry access for `nginx:1.25` and `nginx:1.26` | the environment | Both tags the ConfigMap lists have to be pullable, or the Pod will not start however correct the tag is. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | Pod `app` still exists in namespace `reg` | `LabValidate.bash` |
| B | The Pod's image names a tag the ConfigMap actually lists | `LabValidate.bash` — the tag is looked up in the live ConfigMap's data, not against a hard-coded list |
| C | The Pod is Running and its container is ready | `LabValidate.bash`, after waiting for the pull |
| D | The container is no longer waiting on anything | `LabValidate.bash` |
| E | The ConfigMap `image-tags` is unchanged | `LabValidate.bash` — the live data is compared with the copy taken at setup |

## Gotchas

- **`ImagePullBackOff` is the kubelet's RETRY state, not the first failure.**
  The first time the pull fails the Pod's waiting reason is `ErrImagePull`.
  The kubelet then backs off and retries, and from then on the reason reads
  `ImagePullBackOff`. So `ImagePullBackOff` means "the kubelet has already
  failed at this and is retrying on a timer", not "it is about to give up".

- **The events name the tag that failed.** The status says only that the
  container is waiting. The message `Failed to pull image "nginx:1.99": ...
  not found` is on the Pod's events, so `kubectl describe pod app` is the
  tool for the question. The events are also the only place that says the
  pull failed because the tag does not exist, as opposed to a typo in the
  repository name or a network problem.

- **The ConfigMap holds TAGS, not image references.** The value of the
  `nginx` key is `1.25 1.26`, so the two answers are `nginx:1.25` and
  `nginx:1.26` — the key is the image, the value is the list of tags. Reading
  the value as a whole (and writing `nginx:1.25 1.26`) does not parse.

- **A Pod's container image can be changed in place.** `spec.containers[].image`
  is one of the few parts of a Pod's spec that is not immutable, so
  `kubectl set image pod/app app=nginx:1.25` is enough; the kubelet pulls
  the new image and restarts the container in place. Deleting the Pod is
  unnecessary and loses the thing the task gave you.

- **Editing the ConfigMap to match the Pod is the wrong way round.** It is
  forbidden, and the grader compares the ConfigMap with the copy taken at
  setup. It also destroys the evidence: the ConfigMap is what tells you
  which tags exist.

- **The API server accepts any image reference it can parse.** Nothing
  checks that the tag exists, so `kubectl apply` on the broken Pod succeeds
  and the failure appears afterwards, on the node.

- **A tag that is not in the ConfigMap might still exist in the registry.**
  The ConfigMap is what this question trusts; the registry is what the
  kubelet trusts. They agree here, but the point of the ConfigMap is that you
  do not have to guess or wait for pull errors to find out which tags are
  available.

## Environment requirements

- A cluster with at least one node, and registry access for the `nginx` tags
  the ConfigMap lists.
- No special components. This is plain Pod, ConfigMap and kubelet pull
  behaviour.
