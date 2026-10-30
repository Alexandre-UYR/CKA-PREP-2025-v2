# x4 — Ask the API server directly: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | A working cluster and a `kubectl` that is pointed at it | the cluster | `kubectl proxy` is part of `kubectl`: it reads the same kubeconfig, so it talks to the same API server with the same credentials. |
| 2 | The namespaces `cka-proxy-alpha` and `cka-proxy-beta` | `LabSetUp.bash` | Two namespaces with recognisable names, on top of whatever the cluster already has. They are the proof that the answer is a live listing and not a file written by hand — a response that does not name them is not a response from this cluster. |
| 3 | A client that speaks HTTP — `curl`, or anything else | the machine | The proxy is an HTTP server, not a `kubectl` feature. Talking to it is the point of the exercise. |
| 4 | The namespace names recorded in `/tmp/cka-lab/x4.namespaces` | `LabSetUp.bash` | So the grader checks for the namespaces this setup created, rather than for a list of names it made up. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | The file `/root/namespaces.json` | `LabValidate.bash` |
| B | The file is not empty | `LabValidate.bash` |
| C | The file is JSON — it starts with `{` or `[` | `LabValidate.bash` |
| D | The response holds an `items` array | `LabValidate.bash` |
| E | The array holds every namespace the cluster has, counted live with `kubectl get namespaces --no-headers \| wc -l` | `LabValidate.bash` |
| F | The response names the namespaces the setup created | `LabValidate.bash` |

## Gotchas

- **`kubectl proxy` serves the API under `/api` and `/apis`.** The core API
  group — Pods, Services, Namespaces, ConfigMaps — lives under `/api`, and its
  version is in the path: the namespaces collection is at
  `/api/v1/namespaces`. The other groups (`apps`, `batch`, `networking.k8s.io`
  and the rest) live under `/apis/<group>/<version>`. A path with no version
  in it returns nothing useful.

- **The port is 8001 by default, and it binds to 127.0.0.1.** `kubectl proxy`
  listens on `http://127.0.0.1:8001`. Use `--port=8002` (or any other port) if
  something else already has 8001, and remember that the answer has to be
  fetched from the port the proxy is actually on.

- **The proxy is a foreground process.** It does not return to the shell; it
  sits there until you stop it. It has to run in the background (`kubectl
  proxy &`), or in a second terminal, or the `curl` never happens.

- **`kubectl get namespaces` is not the answer, it is the thing being
  avoided.** The task asks for the API's own answer, not kubectl's rendering
  of it. The difference is visible in the file: `kubectl get ns -o json`
  produces a JSON document too, and it would pass a lazy check — so the
  grader counts the namespaces against the live cluster and requires the
  setup's own namespaces to be named in the response.

- **The response is a `NamespaceList`, and the namespaces are in `items`.**
  The top-level object is the list; each namespace is one element of `items`.
  A response of `{"kind":"NamespaceList", ...,"items":[...]}` is the shape to
  aim for.

- **The proxy needs credentials of its own.** It uses the kubeconfig the
  `kubectl` in your shell is using, which is why it has to be run as the same
  user, from the same environment, as the `kubectl` that can already reach
  the cluster.

## Environment requirements

- A working cluster and a `kubectl` with a kubeconfig that reaches it.
- A client that speaks HTTP (`curl` is enough).
- A free local port for the proxy — 8001 by default.
