#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the Deployment and the Service; deleting it removes both.
k delete namespace cache --ignore-not-found --timeout=120s >/dev/null

# The two files the candidate was asked to produce are on disk, not in the
# cluster, so they have to be removed by hand.
rm -f /root/q3.json /root/q3.txt

echo "w1 reset: namespace cache removed, /root/q3.json and /root/q3.txt deleted"
