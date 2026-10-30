# w14 — A ConfigMap made of files: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | Namespace `cfg` | `LabSetUp.bash` | The ConfigMap and the Deployment both live here, and the task names the namespace. It is created empty. |
| 2 | Directory `/tmp/cka-lab/colors/primary/` | `LabSetUp.bash` | The source material. `kubectl create configmap --from-file` reads the files from disk, so they have to exist before the ConfigMap is created. |
| 3 | Files `cyan`, `magenta`, `yellow`, `blue` | `LabSetUp.bash` | One line each: the colour name. They are the four straightforward keys. |
| 4 | File `black` | `LabSetUp.bash` | Two lines: `black` and `known as key`. It is the file that catches the candidate who assumes one file is one word. |
| 5 | The namespace's ConfigMaps cleared | `LabSetUp.bash` | `kubectl delete configmap --all -n cfg`, so a ConfigMap left over from an earlier attempt cannot be mistaken for the answer, and `kubectl create configmap` does not fail with AlreadyExists. |
| 6 | A Deployment `cfg-app` from an earlier attempt removed | `LabSetUp.bash` | The Deployment is the candidate's answer, not part of the pre-state. A second run of the setup has to start from nothing. |
| 7 | Registry access for `nginx` | the environment | The Deployment runs `nginx`, and the live check is executed inside that pod. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | ConfigMap `colors` in namespace `cfg`, five keys, built from the files | `LabValidate.bash` — exists, exactly five keys, each value equal to the content of its file |
| B | The value of `black` keeps both lines | `LabValidate.bash` — contains `known as key`, counts two lines, equals the whole file |
| C | Deployment `cfg-app` in namespace `cfg`, image `nginx`, 1 replica | `LabValidate.bash` |
| D | The pod template imports the ConfigMap with `envFrom` | `LabValidate.bash` — `envFrom[0].configMapRef.name` is `colors` |
| E | 1 ready replica | `LabValidate.bash` |
| F | A live check from inside the pod | `LabValidate.bash` — `printenv cyan` inside the pod prints the content of the file `cyan` |

## Gotchas

- **`kubectl create configmap --from-file` uses the FILE NAME as the key and the
  FILE CONTENTS as the value.** Point it at the directory and you get one key
  per file: `cyan`, `magenta`, `yellow`, `black`, `blue`. There is no second
  step in which the contents are turned into keys.

- **A multi-line file becomes a multi-line value — it is not split into
  separate keys.** The file `black` holds two lines, so the key `black` holds
  two lines. There are still five keys, not six. A candidate who splits the
  file into `black` and `known as key` has six keys and the grader says so.

- **`envFrom` imports every key of the ConfigMap as an environment variable
  named after the key.** One `configMapRef` gives all five variables at once,
  and there is no list of names to keep in step with the ConfigMap. Listing
  five `env` entries with five `configMapKeyRef`s works too, but a key added
  to the ConfigMap later would not show up.

- **The environment variables only exist inside the pod.** `kubectl get
  configmap` shows the data; `kubectl exec deploy/cfg-app -- printenv cyan`
  shows it in the container. The grader runs the second one, because that is
  the check that proves the Deployment and the ConfigMap are actually joined
  up.

- **A ConfigMap value keeps the bytes of the file.** The files are written
  without a trailing newline, so the values are exactly `cyan`, `magenta`,
  `yellow` and `blue`. A value of `cyan\n` is not the same string as `cyan`,
  and the grader compares them exactly.

- **`kubectl create` will not overwrite.** If the ConfigMap is still there
  from an earlier attempt, delete it first — or run the setup again, which
  clears the namespace for you.

## Environment requirements

- A cluster with at least one node, and registry access for `nginx`.
- A writable `/tmp` on the machine running `kubectl` — the five files live
  there.
- `kubectl` on the machine running the commands. No extra components: this
  is a ConfigMap and a Deployment.
