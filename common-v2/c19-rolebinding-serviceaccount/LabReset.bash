#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The candidate's Role and RoleBinding. Both live in the audit namespace.
k -n audit delete rolebinding pod-reader-binding --ignore-not-found >/dev/null 2>&1 || true
k -n audit delete role pod-reader --ignore-not-found >/dev/null 2>&1 || true

# The namespace holds the ServiceAccount, and it takes the Role and the
# RoleBinding with it.
k delete namespace audit --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

echo "c19 reset: Role pod-reader, RoleBinding pod-reader-binding and namespace audit removed"
