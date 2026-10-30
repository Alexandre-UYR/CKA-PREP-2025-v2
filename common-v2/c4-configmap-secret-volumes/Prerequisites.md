# c4 — ConfigMap and Secret as files and as env vars: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `config` | `LabSetUp.bash` | The ConfigMap, the Secret and the Deployment all live here, and every command is namespaced to it. |
| 2 | A cluster with a working scheduler and a node that can run `nginx:1.25` | the cluster itself | The pod has to start before the mounted volumes and the injected environment variables can be checked. |

There is nothing else. The task is to *create* three objects, so there is no
broken pre-state to reproduce — the difficulty is in getting the shape of the
object right, and in knowing that the two routes into a container are
independent of one another.

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | ConfigMap `app-config` with key `LOG_LEVEL` = `debug` | `LabValidate.bash` |
| B | Secret `app-secret` with key `DB_PASS` = `s3cret` | `LabValidate.bash` (base64-decoded) |
| C | Deployment `app` in namespace `config`, 1 ready replica | `LabValidate.bash` |
| D | A pod template volume sourced from the ConfigMap `app-config` | `LabValidate.bash` |
| E | A pod template volume sourced from the Secret `app-secret` | `LabValidate.bash` |
| F | The `app-config` volume mounted at `/etc/config`, read-only | `LabValidate.bash` |
| G | The `app-secret` volume mounted at `/etc/secret`, read-only | `LabValidate.bash` |
| H | Env var `LOG_LEVEL` from `configMapKeyRef` name `app-config`, key `LOG_LEVEL` | `LabValidate.bash` |
| I | Env var `DB_PASS` from `secretKeyRef` name `app-secret`, key `DB_PASS` | `LabValidate.bash` |
| J | Neither env var is a plain literal value | `LabValidate.bash` |

## Gotchas

- **A `secretKeyRef` must name the Secret AND the key.** Name the Secret
  but get the key wrong and the Pod never starts: it sits in
  `CreateContainerConfigError` with `key "DB_PASSWORD" not found`. The same
  applies to a `configMapKeyRef`. The failure is at container start, not at
  admission, so the Deployment object itself looks perfectly correct.

- **Mounting a Secret as a volume and injecting it as an env var are two
  different routes, and the task wants both.** A volume mount puts the keys
  in the container as *files* (`/etc/secret/DB_PASS`, one file per key, with
  the key as the file name). An env var puts the value in the process
  environment. Neither implies the other. Doing only one is half the answer
  even though the Pod runs happily.

- **The value in a Secret is base64-encoded on the wire.** `kubectl get
  secret -o yaml` shows `DB_PASS: czNjcmV0`, not `s3cret`. That is encoding,
  not encryption - anything in the cluster with read access to the Secret
  can decode it, and `kubectl describe secret` prints the decoded value.
  Decode it before comparing: `kubectl get secret app-secret -o
  jsonpath='{.data.DB_PASS}' | base64 -d`.

- **`stringData` becomes `data`.** You may write the Secret with
  `--from-literal=DB_PASS=s3cret` or by hand with `stringData`, but the API
  server converts `stringData` to `data` on write, so the stored object
  always has base64 in `.data`.

- **A volumeMount refers to a volume by name, and a volume refers to its
  source by name.** `volumes: [{name: config, configMap: {name:
  app-config}}]` and `volumeMounts: [{name: config, mountPath: /etc/config}]`
  — the two `config`s must be the same name, and the inner `name` must be
  the ConfigMap's name. Swapping the mount paths so the Secret lands on
  `/etc/config` produces a Pod that runs perfectly and puts the wrong data
  in the wrong place.

- **The key becomes the file name.** A ConfigMap volume mounted at
  `/etc/config` produces `/etc/config/LOG_LEVEL`, not `/etc/config/config`.
  The task fixes the mount path, and the key name follows from it.

- **Read-only is not the default for a ConfigMap mount.** A ConfigMap volume
  is read-only by nature; a Secret volume is not, and needs `readOnly: true`
  to match what the task asks for.

- **Env var values are strings, and `value` and `valueFrom` are mutually
  exclusive.** Setting `value: debug` on an env var that also has a
  `valueFrom` is rejected by the API server, and a literal `value` is what
  the grader looks for when it says "must not be a plain literal value".

- **An env var change restarts the pod; a ConfigMap volume change does
  not.** Values injected as env vars are read at container start, so they
  need a rollout to take effect. Values in a mounted volume are updated in
  place by kubelet, eventually.

## Environment requirements

- A cluster with at least one node and a working scheduler.
- Registry access for `nginx:1.25`.
- Nothing else. A ConfigMap and a Secret need no storage class, no
  provisioner and no special CNI - they are delivered to the pod by kubelet
  directly.
