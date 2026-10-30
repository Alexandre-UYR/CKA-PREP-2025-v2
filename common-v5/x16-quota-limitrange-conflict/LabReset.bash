#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the LimitRange, the ResourceQuota, the Pod the candidate
# created and the probe Pod the setup tried to create. Deleting it removes all
# of them.
k delete namespace conflict --ignore-not-found --timeout=120s >/dev/null

rm -f /tmp/cka-lab/x16.before /tmp/cka-lab/x16.probe.log

echo "x16 reset: namespace conflict removed (LimitRange, ResourceQuota and Pods), the state files deleted"
