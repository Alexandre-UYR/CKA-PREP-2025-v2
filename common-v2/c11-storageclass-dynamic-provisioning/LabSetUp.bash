#!/bin/bash
set -e

# Pre-state for c11: the namespace the task names, plus a snapshot of the
# cluster's StorageClass state.
#
# The snapshot is the interesting part of this pre-state. The task is to make a
# NEW class the default, and the default flag is per cluster: the class that
# holds it has to give it up. So the lab has to know, before the task starts,
# which class held the flag - otherwise the reset cannot put it back and the
# second attempt starts in a state the first attempt created.
NS=provisioning

mkdir -p /tmp/cka-lab

# Start from a clean pre-state. The StorageClass is cluster-scoped, so it does
# not go with the namespace and has to be removed by name; the claim and the
# Pod do go with the namespace.
kubectl delete storageclass fast --ignore-not-found --wait=true >/dev/null 2>&1 || true
kubectl delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

# Record every StorageClass and the value of its default annotation, so the
# reset can restore each one exactly as it was.
kubectl get sc -o jsonpath='{range .items[*]}{.metadata.name}{"="}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{";"}{end}' \
  > /tmp/cka-lab/c11.sc.before

DEFAULT_BEFORE=$(tr ';' '\n' < /tmp/cka-lab/c11.sc.before | awk -F= '$2=="true"{print $1}' | head -1)

echo "✅ c11 environment ready"
echo "   - namespace: $NS"
echo "   - StorageClasses in the cluster:"
kubectl get sc
echo "   - Default StorageClass before the task: ${DEFAULT_BEFORE:-<none>}"
echo "   - Task: create StorageClass 'fast' (rancher.io/local-path, WaitForFirstConsumer),"
echo "     make it the only default class, then a PVC 'data' and a Pod 'writer' in $NS"
