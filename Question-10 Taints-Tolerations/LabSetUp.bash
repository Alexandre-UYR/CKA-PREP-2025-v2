#!/bin/bash
set -e

# The lab runs against the playground as it is. The question needs at least one
# schedulable node, and the reset needs to find the tainted node again even if
# the candidate picked a different one, so record the node list.
mkdir -p /tmp/cka-lab
kubectl get nodes -o name > /tmp/cka-lab/q10.nodes

echo "# For this lab you can just use the killercoda playground as it is, no adjustments needed"
echo
echo "Nodes in the cluster:"
kubectl get nodes -o wide
echo
echo "Existing taints:"
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.spec.taints}{"\n"}{end}'
