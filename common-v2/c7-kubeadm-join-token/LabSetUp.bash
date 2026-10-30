#!/bin/bash
set -e

# c7 — Prepare a node join
#
# There is nothing to create here: the cluster is the pre-state. This question
# runs on the CONTROL-PLANE node, not through kubectl, because the answer is
# built with kubeadm and from the control plane's own PKI.
#
# What the setup does do is record the bootstrap tokens that already exist, so
# the grader can tell which token the candidate created, and clear any join
# command left over from a previous attempt.

STATE=/tmp/cka-lab
TOKENS_FILE="$STATE/c7.tokens"
JOIN_FILE=/root/kubeadm-join.sh

mkdir -p "$STATE"

# The candidate has to write the join command themselves: start from nothing.
rm -f "$JOIN_FILE" 2>/dev/null || true

# --------------------------------------------------------------- kubeadm ----

if ! command -v kubeadm >/dev/null 2>&1; then
  echo "kubeadm is NOT installed on this machine."
  echo "c7 has to run on the control-plane node of a kubeadm cluster, where"
  echo "kubeadm, /etc/kubernetes/pki/ca.crt and the admin kubeconfig live."
  echo "The file checks will still run; the kubeadm checks will be skipped."
  : > "$TOKENS_FILE"
  echo "c7 environment ready (degraded: no kubeadm here)"
  exit 0
fi

if [ ! -f /etc/kubernetes/pki/ca.crt ]; then
  echo "WARNING: /etc/kubernetes/pki/ca.crt is not here, so this machine does not" >&2
  echo "         look like a kubeadm control-plane node. The kubeadm checks" >&2
  echo "         will probably be skipped." >&2
fi

if [ "$(id -u)" != "0" ]; then
  echo "WARNING: you are not root. /root/kubeadm-join.sh is not writable, and" >&2
  echo "         kubeadm needs root to read the admin kubeconfig." >&2
fi

# ------------------------------------------------------------ the tokens ----

# Record the tokens that exist before the exercise, so the grader can tell
# which one is new. `kubeadm token list` prints the token ID (the first six
# characters of the token) in the first column; the secret itself is not shown.
kubeadm token list 2>/dev/null | awk 'NF>0 {print $1}' | grep -E '^[a-z0-9]{6}$' > "$TOKENS_FILE" || true

echo "c7 environment ready"
echo "   - kubeadm: $(command -v kubeadm)"
echo "   - tokens before the exercise: $(wc -l < "$TOKENS_FILE" | tr -d ' ')"
echo "   - join file to write: $JOIN_FILE"
echo "   - Task: create a bootstrap token and write the kubeadm join command there"
