#!/bin/bash
set -e

# The pre-state for c29 is the cluster itself. Nothing is created and nothing
# is changed - the setup only records what the cluster looks like, so the
# candidate can compare their answer against it and the reset has nothing to
# undo beyond the answer file.
mkdir -p /tmp/cka-lab

kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.taints}{"\n"}{end}' \
  > /tmp/cka-lab/c29.nodes

NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')

echo "✅ c29 environment ready"
echo "   - nodes in the cluster: ${NODE_COUNT}"
echo "   - Task: count the Ready, schedulable nodes, excluding the control plane,"
echo "     and write the number to /root/ready-nodes.txt"
if [ "${NODE_COUNT:-0}" -lt 2 ] 2>/dev/null; then
  echo "   ⚠️  This cluster has only one node, so the answer will be 0."
  echo "      The question needs at least two nodes to be interesting."
fi
kubectl get nodes -o wide
