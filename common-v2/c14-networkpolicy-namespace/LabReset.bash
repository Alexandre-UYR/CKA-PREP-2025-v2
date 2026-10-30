#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The candidate's policy and any probe pods they left behind.
k -n netpol delete netpol allow-frontend --ignore-not-found --timeout=60s >/dev/null 2>&1 || true
k -n frontend delete pod probe --ignore-not-found --wait=false >/dev/null 2>&1 || true
k -n frontend delete pod probe-frontend --ignore-not-found --wait=false >/dev/null 2>&1 || true
k -n other delete pod probe --ignore-not-found --wait=false >/dev/null 2>&1 || true
k -n other delete pod probe-other --ignore-not-found --wait=false >/dev/null 2>&1 || true

# The namespace label, if the namespace is still around.
k label namespace frontend name- --overwrite >/dev/null 2>&1 || true

# The namespaces themselves hold every other object the question produced:
# the api Deployment and Service, the tester Deployments, the policy.
k delete namespace netpol   --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
k delete namespace frontend --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
k delete namespace other    --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

echo "c14 reset: namespaces netpol, frontend and other removed (label name=frontend removed)"
