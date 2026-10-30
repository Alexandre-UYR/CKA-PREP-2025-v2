#!/bin/bash
# Reset for c28 (find the hottest Pod): back to the pre-state so the question
# can be attempted again from scratch.
set -uo pipefail
k(){ kubectl "$@"; }

NS=metrics

# The namespace takes the three Deployments with it. Run the setup again
# afterwards to rebuild the pre-state.
k delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# The files the candidate produced live outside the cluster, so they have to
# be removed by hand.
rm -f /root/hot-pod.txt /root/hot-pod-command.txt

echo "c28 reset: namespace $NS removed, /root/hot-pod.txt and /root/hot-pod-command.txt deleted."
echo "         Run './lab.sh c28' to rebuild the pre-state."
