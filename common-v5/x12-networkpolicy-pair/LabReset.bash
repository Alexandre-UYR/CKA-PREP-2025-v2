#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

LABDIR=/tmp/cka-lab

# The policies are removed by name as well as with the namespace, in case one
# of them was created somewhere else.
for n in netpol frontend; do
  k -n "$n" delete networkpolicy --all --ignore-not-found >/dev/null 2>&1 || true
done

# The namespaces hold the Pods, the Services and the policies.
k delete namespace netpol --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
k delete namespace frontend --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

echo "x12 reset: the NetworkPolicies and the namespaces netpol and frontend removed"
