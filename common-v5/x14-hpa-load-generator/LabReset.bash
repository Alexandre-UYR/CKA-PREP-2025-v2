#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the Deployment, the Service, the HPA and the load
# generator, so deleting it removes all of them.
k delete namespace autoscale --ignore-not-found --timeout=120s >/dev/null

# The HPA may have been created in another namespace by mistake; remove it
# wherever it is.
k delete hpa hpa --all-namespaces --ignore-not-found >/dev/null 2>&1 || true

# The metrics server the candidate installed. The APIService goes with it:
# a registered APIService pointing at a service that is not there makes the
# metrics API hang instead of failing fast.
k delete deployment metrics-server -n kube-system --ignore-not-found >/dev/null 2>&1 || true
k delete serviceaccount metrics-server -n kube-system --ignore-not-found >/dev/null 2>&1 || true
k delete service metrics-server -n kube-system --ignore-not-found >/dev/null 2>&1 || true
k delete clusterrole system:metrics-server --ignore-not-found >/dev/null 2>&1 || true
k delete clusterrole system:aggregated-metrics-reader --ignore-not-found >/dev/null 2>&1 || true
k delete clusterrolebinding system:metrics-server --ignore-not-found >/dev/null 2>&1 || true
k delete clusterrolebinding metrics-server:system:auth-delegator --ignore-not-found >/dev/null 2>&1 || true
k delete rolebinding metrics-server-auth-reader -n kube-system --ignore-not-found >/dev/null 2>&1 || true
k delete apiservice v1beta1.metrics.k8s.io --ignore-not-found >/dev/null 2>&1 || true

rm -f /tmp/cka-lab/x14.*

echo "x14 reset: namespace autoscale removed (Deployment, Service, HPA and load generator), the metrics server removed from kube-system"
