#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

k delete ns cka-q8-test --ignore-not-found --wait=false >/dev/null 2>&1 || true

# Remove Calico.
k -n tigera-operator delete deployment tigera-operator --ignore-not-found >/dev/null 2>&1 || true
k delete ns tigera-operator --ignore-not-found --wait=false >/dev/null 2>&1 || true
k -n kube-system delete ds calico-node --ignore-not-found --wait=false >/dev/null 2>&1 || true
k delete crd crd.projectcalico.org v1.projectcalico.org --ignore-not-found >/dev/null 2>&1 || true

rm -f /tmp/cka-lab/q8.*

echo "Q8 reset"
echo "NOTE: removing the CNI takes the cluster's pod networking down. Reinstall a CNI"
echo "      (the same manifest the candidate used) before using this cluster for anything else."
