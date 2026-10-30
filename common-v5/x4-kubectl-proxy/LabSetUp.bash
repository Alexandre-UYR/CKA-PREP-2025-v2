#!/bin/bash
set -e

# x4 - Ask the API server directly
#
# The pre-state is the cluster itself, plus two namespaces with recognisable
# names. They are there so that the grader can tell a live listing from a
# file the candidate wrote by hand: the response has to name them.
#
# The setup does not start the proxy and does not fetch anything. That is the
# candidate's job.

LABDIR=/tmp/cka-lab
NAMESPACES="cka-proxy-alpha cka-proxy-beta"
NAMELIST="$LABDIR/x4.namespaces"

mkdir -p "$LABDIR"

# ---- the namespaces ---------------------------------------------------------
# Created with apply, so running the setup twice leaves the same state.

for NS in $NAMESPACES; do
  kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
done

printf '%s\n' $NAMESPACES > "$NAMELIST"

# ---- report -----------------------------------------------------------------

LIVE=$(kubectl get namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')

echo "✅ x4 environment ready"
echo "   - namespaces created: $NAMESPACES"
echo "   - the cluster has $LIVE namespaces in total"
echo "   - recorded in: $NAMELIST"
echo "   - Task: use `kubectl proxy` to list every namespace through the API"
echo "     and save the response to /root/namespaces.json"

if [ -z "$LIVE" ] || [ "$LIVE" -lt 2 ] 2>/dev/null; then
  echo "   ⚠️  The cluster reports $LIVE namespaces. The grader counts the" >&2
  echo "      namespaces live, so a short list will not pass." >&2
fi
