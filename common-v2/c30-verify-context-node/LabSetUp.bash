#!/bin/bash
set -e

# The pre-state for c30 is the cluster itself, plus the shell you are sitting
# in. Nothing is created and nothing is changed - the point of the question is
# to find out where you are.
mkdir -p /tmp/cka-lab

CTX="$(kubectl config current-context 2>/dev/null || true)"
HOST="$(hostname 2>/dev/null || true)"

printf '%s\n' "$CTX" > /tmp/cka-lab/c30.context
printf '%s\n' "$HOST" > /tmp/cka-lab/c30.host

echo "✅ c30 environment ready"
echo "   - Task: write the current kubectl context and the node's hostname"
echo "     into /root/current-context.txt and /root/current-node.txt"
echo
echo "Starting point, for you to check yourself against:"
echo "   context: ${CTX:-<unknown>}"
echo "   hostname: ${HOST:-<unknown>}"
