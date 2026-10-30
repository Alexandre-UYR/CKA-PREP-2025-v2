#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

LABDIR=/tmp/cka-lab

# The namespace holds the ServiceAccount, the Role, the RoleBinding and
# anything else the candidate put in it.
k delete namespace rbac --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# The kubeconfig is the candidate's output, and it lives outside the
# namespace, so it has to be removed by name.
rm -f /root/rbac.kubeconfig

echo "x11 reset: namespace rbac removed, /root/rbac.kubeconfig deleted"
