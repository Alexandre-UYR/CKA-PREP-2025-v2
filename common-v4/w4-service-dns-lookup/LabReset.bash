#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the redis Pod, the Service and the looker Pod; deleting
# it removes all of them.
k delete namespace dns-demo --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# The answer file is on disk, not in the cluster, so it has to be removed by
# hand.
rm -f /root/q5.txt

echo "w4 reset: namespace dns-demo removed, /root/q5.txt deleted"
