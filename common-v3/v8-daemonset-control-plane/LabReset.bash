#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }
LABDIR="/tmp/cka-lab"

# The namespace holds the DaemonSet and its pods, so deleting the namespace
# removes them with everything else. The DaemonSet is deleted by name as well,
# in case the candidate put it in a namespace of their own choosing.
k delete namespace ds --ignore-not-found --timeout=120s >/dev/null
k delete daemonset agent --all-namespaces --ignore-not-found >/dev/null 2>&1 || true

# The control-plane taint belongs to the cluster, not to this question, so it
# stays. The monitoring=yes label is part of the pre-state, so it stays too.
# The setup's own state files are removed; the next setup recreates them.

rm -f "$LABDIR/v8.taint" "$LABDIR/v8.cpnode" "$LABDIR/v8.monitor" "$LABDIR/v8.nodes"

echo "v8 reset: namespace ds and DaemonSet agent removed"
echo "v8 reset: the control-plane taint and the monitoring=yes label were left in place"
