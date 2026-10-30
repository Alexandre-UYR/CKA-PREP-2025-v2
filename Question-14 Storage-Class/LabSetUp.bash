#!/bin/bash
set -e

# The lab runs against the playground as it is. What the question needs is not a
# new object but the cluster's CURRENT StorageClass state, so that the reset can
# put the default flag back where it was and the validator can prove that
# switching the default did not disturb any existing claim.
mkdir -p /tmp/cka-lab

kubectl get sc -o jsonpath='{range .items[*]}{.metadata.name}{"="}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{";"}{end}' \
  > /tmp/cka-lab/q14.sc.before

kubectl get pvc -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{"="}{.spec.storageClassName}{";"}{end}' \
  | tr ';' '\n' | sort > /tmp/cka-lab/q14.pvc.before

DEFAULT_BEFORE=$(tr ';' '\n' < /tmp/cka-lab/q14.sc.before | awk -F= '$2=="true"{print $1}' | head -1)

echo "# For this lab you can just use the killercoda playground as it is, no adjustments needed"
echo
echo "StorageClasses in the cluster:"
kubectl get sc
echo
echo "Default StorageClass before the task: ${DEFAULT_BEFORE:-<none>}"
echo "Existing PVCs recorded: $(wc -l < /tmp/cka-lab/q14.pvc.before | tr -d ' ')"
