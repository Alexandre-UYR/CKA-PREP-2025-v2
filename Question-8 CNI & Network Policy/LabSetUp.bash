#!/bin/bash
set -e

# The lab runs against the playground as it is. What matters is knowing what the
# cluster looked like before the candidate swapped the CNI, so the reset can say
# what it removed.
mkdir -p /tmp/cka-lab

kubectl get nodes -o name > /tmp/cka-lab/q8.nodes
kubectl get ds -n kube-system -o name > /tmp/cka-lab/q8.ds.before 2>/dev/null || true

echo "# For this lab you can just use the killercoda playground as it is, no adjustments needed"
echo
echo "Nodes:"
kubectl get nodes -o wide
echo
echo "CNI currently installed (kube-system DaemonSets):"
kubectl get ds -n kube-system 2>/dev/null || echo "  <none>"
echo
echo "The candidate installs a CNI from a manifest. Choose one that enforces NetworkPolicy:"
echo "  Flannel  v0.26.1  https://github.com/flannel-io/flannel/releases/download/v0.26.1/kube-flannel.yml"
echo "  Calico   v3.28.2  https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/tigera-operator.yaml"
