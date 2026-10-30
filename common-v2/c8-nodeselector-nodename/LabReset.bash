#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

k delete namespace scheduling --ignore-not-found --timeout=120s >/dev/null

# The label has to come off every node, not just the one this run used: the
# candidate may have labelled a different node.
for n in $(k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
  k label node "$n" workload- --overwrite >/dev/null 2>&1 || true
done

rm -f /tmp/cka-lab/c8.node

echo "c8 reset: namespace scheduling removed, the workload=general label is off every node"
