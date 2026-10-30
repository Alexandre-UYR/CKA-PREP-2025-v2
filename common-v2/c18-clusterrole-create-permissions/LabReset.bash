#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The candidate's ClusterRole and ClusterRoleBinding. Both are cluster-scoped,
# so they are named without a namespace.
k delete clusterrolebinding builder-workloads --ignore-not-found >/dev/null 2>&1 || true
k delete clusterrole workload-creator --ignore-not-found >/dev/null 2>&1 || true

# The namespace holds the ServiceAccount.
k delete namespace ops --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

echo "c18 reset: ClusterRole workload-creator, ClusterRoleBinding builder-workloads and namespace ops removed"
