#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The candidate's Gateway and HTTPRoute. They may be in any namespace, so
# sweep the whole cluster.
k delete gateways.gateway.networking.k8s.io --all -A --ignore-not-found --timeout=60s >/dev/null 2>&1 || true
k delete httproutes.gateway.networking.k8s.io --all -A --ignore-not-found --timeout=60s >/dev/null 2>&1 || true

# The pre-state workload and service.
k -n default delete deploy web --ignore-not-found --timeout=60s >/dev/null 2>&1 || true
k -n default delete svc web --ignore-not-found --timeout=60s >/dev/null 2>&1 || true

# DELIBERATELY NOT deleting the Gateway API CRDs. They are cluster-scoped, and
# deleting a CRD destroys every object of that kind in the cluster. The setup
# re-applies the standard set idempotently when they are already present.
echo "c17 reset: Gateway, HTTPRoute, Deployment web and Service web removed (Gateway API CRDs left in place)"
