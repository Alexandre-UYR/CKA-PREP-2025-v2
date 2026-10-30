#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

LABDIR=/tmp/cka-lab

# The namespace holds the three Deployments and the Pods they own.
k delete namespace metrics --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# The metrics server the candidate installed lives in kube-system, outside
# the namespace, so it has to be removed by name.
k -n kube-system delete deployment metrics-server --ignore-not-found --timeout=60s >/dev/null 2>&1 || true
k -n kube-system delete serviceaccount metrics-server --ignore-not-found >/dev/null 2>&1 || true
k delete apiservice v1beta1.metrics.k8s.io --ignore-not-found >/dev/null 2>&1 || true

# The two files the candidate was asked to produce.
rm -f /root/busiest-node.txt
rm -f /root/hottest-pod.txt

echo "x13 reset: namespace metrics removed, the metrics server removed from"
echo "           kube-system, /root/busiest-node.txt and /root/hottest-pod.txt deleted"
