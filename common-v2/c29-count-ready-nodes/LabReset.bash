#!/bin/bash
set -uo pipefail

# The setup changed nothing in the cluster, so the reset only removes what the
# candidate produced. The control-plane taint is left alone: it is part of the
# cluster's normal state, not something this question introduced.
rm -f /root/ready-nodes.txt
rm -f /tmp/cka-lab/c29.nodes

echo "c29 reset: /root/ready-nodes.txt removed"
