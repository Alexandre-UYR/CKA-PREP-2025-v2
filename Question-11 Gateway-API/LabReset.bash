#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# --- the candidate's deliverables ---
k delete gateway web-gateway --ignore-not-found --wait=false >/dev/null 2>&1 || true
k delete httproute web-route --ignore-not-found --wait=false >/dev/null 2>&1 || true

# --- the pre-state LabSetUp.bash created ---
k delete ingress web --ignore-not-found --wait=false >/dev/null 2>&1 || true
k delete secret web-tls --ignore-not-found >/dev/null 2>&1 || true
k delete deployment web-deployment --ignore-not-found --wait=false >/dev/null 2>&1 || true
k delete service web-service --ignore-not-found >/dev/null 2>&1 || true
k delete gatewayclass nginx-class --ignore-not-found >/dev/null 2>&1 || true

# NOTE: the Gateway API CRDs (gateways.gateway.networking.k8s.io,
#       httproutes.gateway.networking.k8s.io, gatewayclasses..., ...) are
#       deliberately LEFT IN PLACE. They are cluster-scoped and shared with
#       any other Gateway API question on the same cluster, and LabSetUp.bash
#       re-applies them idempotently, so deleting them buys nothing and would
#       break unrelated questions.

echo "Q11 reset: Gateway web-gateway, HTTPRoute web-route, Ingress web, Secret web-tls,"
echo "             Deployment web-deployment, Service web-service and GatewayClass"
echo "             nginx-class removed. The Gateway API CRDs were left in place."
