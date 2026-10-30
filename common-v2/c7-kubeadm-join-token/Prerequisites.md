# c7 — Prepare a node join: prerequisite inventory

## Prerequisites

| # | Prerequisite | Created by | Why the question needs it |
|---|---|---|---|
| 1 | A kubeadm-built cluster, and this machine **is** the control-plane node | the cluster itself | The task is not a `kubectl` task. The join command is built from `kubeadm` and from the control plane's own PKI, so the script has to run where those files are. |
| 2 | `kubeadm` on `PATH` | the cluster installation | `kubeadm token create` is how a bootstrap token is made, and `kubeadm token list` is how you show the token is valid. Without kubeadm these two checks are skipped rather than failed. |
| 3 | `/etc/kubernetes/pki/ca.crt` | kubeadm | The CA certificate hash in the join command is derived from this file. Without it the joining node has no way to verify that the API server it is talking to is the real one. |
| 4 | The admin kubeconfig (`/etc/kubernetes/admin.conf`) | kubeadm | `kubeadm token create` and `kubeadm token list` talk to the API server through it, so kubeadm needs root and the admin credentials. |
| 5 | The API server address and port | the cluster | One of the three things the join command must carry. It comes from the kubeconfig's `server:` field, or from the `kubernetes` Service in the `default` namespace. |
| 6 | The bootstrap tokens that already existed, recorded in `/tmp/cka-lab/c7.tokens` | `LabSetUp.bash` | The task asks for a *new* token. The grader compares the token list now against the list from setup time, so it can tell that a token was created rather than that an old one was reused. |
| 7 | `/root/kubeadm-join.sh` removed | `LabSetUp.bash` | The candidate has to produce the file. Any leftover from a previous attempt is deleted so the file's contents are the candidate's own work. |

## What the candidate must create

| # | Deliverable | Checked by |
|---|---|---|
| A | `/root/kubeadm-join.sh` exists and is not empty | `LabValidate.bash` |
| B | It contains a `kubeadm join` command | `LabValidate.bash` |
| C | It contains a `--token` argument | `LabValidate.bash` |
| D | It contains a `--discovery-token-ca-cert-hash` argument | `LabValidate.bash` |
| E | It contains the CA certificate hash (`sha256:...`) | `LabValidate.bash` |
| F | It contains an `https://` API server endpoint | `LabValidate.bash` |
| G | The token in the file appears in `kubeadm token list` | `LabValidate.bash` |
| H | `kubeadm token list` shows at least one token that is new | `LabValidate.bash` |

## Why this pre-state is the cluster itself

There is nothing to provision here, and that is unusual enough to be worth
saying out loud. Most questions in this set reproduce a broken environment;
this one reproduces a *healthy* one and asks the candidate to change the
cluster's bootstrap credentials.

That makes the prerequisites invisible, which is exactly the skill the exam
tests. Nothing in the API server says "there is a bootstrap token here" —
bootstrap tokens live in the `kube-system` namespace as `Secret` objects of
type `bootstrap-token-<id>`, and they expire. The candidate has to know that
`kubeadm token create` is the tool, that `kubeadm token list` is how you
confirm the token exists, and that the CA hash is not optional.

## Gotchas

- **The join command needs three things, and a token alone is not enough.**
  It needs the **API server address and port**, a **token**, and the **CA
  certificate hash**. The hash is what lets the joining node confirm that the
  API server it reaches is the one it is supposed to trust — without it the
  node has no way to verify the certificate it is handed. The grader checks
  all three.

- **The CA hash is a hash of the CA's *public key*, in `sha256:` form.** It
  is not a hash of the certificate file:

  ```bash
  openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt \
    | openssl rsa -pubin -outform der 2>/dev/null \
    | openssl dgst -sha256 -hex | sed 's/^.* //'
  ```

  That last `sed` is what turns `SHA2-256(stdin)= abcdef...` into the bare
  `sha256:abcdef...` that the join command needs.

- **`kubeadm token create --print-join-command` gives you most of it, but
  not the `https://`.** The printed command uses the API server's *advertise
  address* — `10.0.0.1:6443`, a bare host and port, with no scheme. The
  grader wants an endpoint the node can use as-is, so take the URL from the
  kubeconfig, where it is written `https://<host>:<port>`.

- **`kubeadm token list` shows the token ID, not the token.** The first
  column is the six-character ID — the first half of the token, before the
  dot. The secret half is never printed again. So `kubeadm token list`
  showing `a1b2c3` means the token `a1b2c3.0123456789abcdef` exists.

- **The token in the file has to be one of the live tokens.** A command that
  quotes a token from a blog post, or a token that has since been deleted,
  fails the check even though the file looks perfect.

- **The token has to be new.** The grader recorded the tokens that existed
  before the exercise, so reusing one of those does not count. `kubeadm token
  create` makes a new one every time.

- **`kubeadm token delete <id>` takes the ID**, not the whole token, and it
  is the right way to clean up — the token lives in the API server until it
  expires or is deleted.

- **kubeadm needs root.** It reads the admin kubeconfig, which is only
  readable by root. Running it as a normal user fails with a permission
  error rather than anything informative.

- **This is a control-plane task.** Running it from a laptop that merely
  *talks to* the cluster does not work: `kubeadm` is not there, and the CA
  certificate is not there either.

## Environment requirements

- A kubeadm-built cluster, and a shell on its control-plane node.
- `kubeadm` on `PATH`, matching the cluster's Kubernetes version.
- Root, or a user that can read `/etc/kubernetes/admin.conf` and write
  `/root/`.
- `/etc/kubernetes/pki/ca.crt` present.
- The API server reachable from the control-plane node, so `kubeadm token
  create` can talk to it.
- If `kubeadm` is missing, the lab still runs: the file's existence and
  contents are graded, and the two kubeadm-dependent checks are skipped with
  the reason printed.
