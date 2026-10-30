#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# --- the candidate's deliverable: the NetworkPolicy they applied in ns backend ---
k -n backend delete networkpolicy --all --ignore-not-found --wait=false >/dev/null 2>&1 || true

# --- any leftover probe pods ---
k -n frontend delete pod np-test --ignore-not-found --wait=false >/dev/null 2>&1 || true
k -n default delete pod np-test-neg --ignore-not-found --wait=false >/dev/null 2>&1 || true

# --- the pre-state ---
k delete ns frontend --ignore-not-found --wait=false >/dev/null 2>&1 || true
k delete ns backend --ignore-not-found --wait=false >/dev/null 2>&1 || true

# --- the three candidate policy files the question handed over ---
rm -f /root/network-policies/network-policy-1.yaml \
      /root/network-policies/network-policy-2.yaml \
      /root/network-policies/network-policy-3.yaml 2>/dev/null || true
rmdir /root/network-policies 2>/dev/null || true

echo "Q13 reset: NetworkPolicy removed from ns backend, namespaces frontend and backend"
echo "             deleted, and the three files in /root/network-policies removed."
