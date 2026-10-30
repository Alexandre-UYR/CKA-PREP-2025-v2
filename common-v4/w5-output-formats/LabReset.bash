#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the Deployment and the Service; deleting it removes
# both.
k delete namespace reports --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# The two answer files are on disk, not in the cluster, so they have to be
# removed by hand.
rm -f /root/q6a.txt /root/q6b.txt

echo "w5 reset: namespace reports removed, /root/q6a.txt and /root/q6b.txt deleted"
