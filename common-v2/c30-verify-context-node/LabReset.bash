#!/bin/bash
set -uo pipefail

# The setup changed nothing in the cluster, so the reset only removes what the
# candidate produced.
rm -f /root/current-context.txt
rm -f /root/current-node.txt
rm -f /tmp/cka-lab/c30.context /tmp/cka-lab/c30.host

echo "c30 reset: /root/current-context.txt and /root/current-node.txt removed"
