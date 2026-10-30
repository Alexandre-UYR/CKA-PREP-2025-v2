#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the ServiceAccount, the Role and the RoleBinding, so
# deleting it removes the whole hole - including anything the candidate
# created while working on it.
k delete namespace esc --ignore-not-found --timeout=120s >/dev/null

echo "v15 reset: namespace esc removed"
