#!/bin/bash
set -e

# c8 needs two things from the cluster: the namespace the task names, and a
# node carrying the label the task refers to. The node name is recorded so the
# reset can take the label off again even if the candidate ended up labelling
# a different node.

NS=scheduling
LABDIR=/tmp/cka-lab

mkdir -p "$LABDIR"

# Pick the first Ready, schedulable node that is not a control-plane node.
WORKER=""
for n in $(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'); do
  CP=$(kubectl get node "$n" -o jsonpath='{.metadata.labels.node-role\.kubernetes\.io/control-plane}' 2>/dev/null)
  MASTER=$(kubectl get node "$n" -o jsonpath='{.metadata.labels.node-role\.kubernetes\.io/master}' 2>/dev/null)
  UNSCHED=$(kubectl get node "$n" -o jsonpath='{.spec.unschedulable}' 2>/dev/null)
  READY=$(kubectl get node "$n" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  if [ -n "$CP" ]; then continue; fi
  if [ -n "$MASTER" ]; then continue; fi
  if [ "$UNSCHED" = "true" ]; then continue; fi
  if [ "$READY" != "True" ]; then continue; fi
  WORKER="$n"
  break
done

if [ -z "$WORKER" ]; then
  echo "c8 needs at least one Ready, schedulable, non-control-plane node." >&2
  echo "Nodes in this cluster:" >&2
  kubectl get nodes -o wide >&2
  exit 1
fi

# Take the label off every node first, so a second run cannot leave a second
# node carrying it: the task's node has to be the only one that has it.
for n in $(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'); do
  kubectl label node "$n" workload- --overwrite >/dev/null 2>&1 || true
done

kubectl label node "$WORKER" workload=general --overwrite

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

printf '%s\n' "$WORKER" > "$LABDIR/c8.node"

echo "✅ c8 environment ready"
echo "   - namespace: $NS"
echo "   - node labelled workload=general: $WORKER"
echo "   - Task: create two Pods on that node, one with nodeName and one with nodeSelector"
