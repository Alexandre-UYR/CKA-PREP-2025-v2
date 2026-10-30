# w13 — The same Secret, two ways: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `secrets` | `LabSetUp.bash` | The Secret and the Deployment live here, and the task names the namespace. It is recreated on every run, so the pre-state is always the same. |
| 2 | Secret `app-secret` with the key `username` = `admin` | `LabSetUp.bash` — `kubectl create secret generic` | One of the two keys the Deployment has to consume. The values are plain and known so that the grader can check what the pod actually sees. |
| 3 | Secret `app-secret` with the key `password` = `s3cr3t` | `LabSetUp.bash` | The second key. The task says BOTH keys, so a Deployment that only wires up one of them is half an answer. |
| 4 | Nothing else in the namespace | `LabSetUp.bash` | There is no pre-existing Deployment to copy, no Service to inspect, no other consumer of the Secret. The candidate builds the whole thing from the Secret. |
| 5 | Registry access for `nginx` | the environment | The pod has to start and stay running, or there is nothing to `exec` into and the live checks cannot be made. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | Deployment `secret` exists in namespace `secrets`, with 1 ready replica | `LabValidate.bash` |
| B | Its pod template sources the Secret's keys as environment variables — either an `envFrom` with a `secretRef` naming `app-secret`, or two `env` entries each with a `secretKeyRef` naming `app-secret` with the keys `username` and `password` | `LabValidate.bash` |
| C | The Secret is mounted as a volume at `/etc/secret` | `LabValidate.bash` |
| D | Inside the pod, `printenv username` gives `admin` | `LabValidate.bash` — a live check |
| E | Inside the pod, `printenv password` gives `s3cr3t` | `LabValidate.bash` — a live check |
| F | Inside the pod, `/etc/secret/username` holds `admin` | `LabValidate.bash` — a live check |

The last three are live checks: the validator runs them in the container, so
they prove the wiring works rather than merely that the manifest looks right.

## Gotchas

- **A Secret mounted as a volume appears as one FILE PER KEY, named after the
  key.** Mounting `app-secret` at `/etc/secret` gives you
  `/etc/secret/username` and `/etc/secret/password` — not one file called
  `app-secret`, and not a directory per key.

- **The kubelet decodes the base64 for you.** What is in the Secret's
  `.data` is base64, but what lands in the mounted file is the plain value:
  `/etc/secret/username` holds `admin`, not `YWRtaW4=`. The same is true of
  the environment variable. If you find yourself decoding base64 by hand,
  something is wrong.

- **`envFrom` imports EVERY key of the Secret, and the environment variable
  names are the KEY names.** With
  `envFrom: [{secretRef: {name: app-secret}}]`, the container gets
  `username` and `password` as environment variables, named after the keys.
  There is no way to rename them with `envFrom`: no `name:` field, no
  `prefix` that would help you here, and the keys simply arrive as they are.
  If you need different variable names, you need individual `env` entries
  with `secretKeyRef` instead.

- **Two `env` entries with `secretKeyRef` are the alternative, and they are
  equally correct.** Each entry names a variable, and each points at one key
  of one Secret:

  ```yaml
  env:
    - name: username
      valueFrom:
        secretKeyRef:
          name: app-secret
          key: username
    - name: password
      valueFrom:
        secretKeyRef:
          name: app-secret
          key: password
  ```

  The variable name and the key name have to agree if you want `printenv
  username` to work, because the variable name is yours to choose and the key
  name is the Secret's.

- **The two mechanisms are independent.** A Deployment can do both, and this
  one has to: `envFrom` (or the `env` entries) for the environment, and a
  `volumes` entry plus a `volumeMount` for the files. A `volumeMount` alone
  does not create environment variables, and an `env` entry alone does not
  create a file.

- **The volume has to be declared in two places.** The `volumes` list on the
  pod template says where the Secret comes from (`secretName: app-secret`),
  and the container's `volumeMounts` says where it is put (`mountPath:
  /etc/secret`). Leaving either out means the other one does nothing.

- **A missing key makes the pod fail to start, not fail silently.** A
  `secretKeyRef` naming a key that does not exist leaves the pod in
  `CreateContainerConfigError`, and the message in `kubectl describe pod`
  names the missing key.

- **The values must not be hard-coded.** The task is about consuming the
  Secret, and the validator checks where the values come from, not just what
  they happen to be.

## Environment requirements

- A working cluster with at least one node, and registry access for `nginx`.
- A kubelet that supports projected Secret volumes — every mainstream CNI and
  every current kubelet does.
- No special components. This is ordinary pod configuration.
- The container needs `printenv` and `cat` for the live checks; the `nginx`
  image has both.
