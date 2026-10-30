#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }
LABDIR=/tmp/cka-lab

# The namespace holds the DaemonSet, its pods and the ConfigMap; deleting it
# removes all three.
k delete namespace agent --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# The setup's probe namespace, if a run was interrupted.
k delete namespace agent-probe --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# The DaemonSet is deleted by name as well, in case the candidate put it in a
# namespace of their own choosing.
k delete daemonset fluentd --all-namespaces --ignore-not-found >/dev/null 2>&1 || true

# The taint belongs to the cluster, not to this question - unless the setup
# added it, in which case the reset takes it away again.
ADDED=""
[ -f "$LABDIR/w7.taint.added" ] && ADDED="$(cat "$LABDIR/w7.taint.added" 2>/dev/null)"
if [ "$ADDED" = "yes" ] && [ -f "$LABDIR/w7.taint" ]; then
  CP_NODE=""
  [ -f "$LABDIR/w7.cpnode" ] && CP_NODE="$(cat "$LABDIR/w7.cpnode" 2>/dev/null)"
  TAINT="$(cat "$LABDIR/w7.taint" 2>/dev/null)"
  if [ -n "$CP_NODE" ] && [ -n "$TAINT" ]; then
    k taint node "$CP_NODE" "$TAINT-" >/dev/null 2>&1 || true
  fi
  echo "w7 reset: the taint $TAINT this setup added to $CP_NODE was removed"
else
  echo "w7 reset: the cluster's own taints were left in place"
fi

rm -f "$LABDIR/w7.taint" "$LABDIR/w7.taint.added" "$LABDIR/w7.cpnode" "$LABDIR/w7.nodes"

echo "w7 reset: namespace agent and DaemonSet fluentd removed"
