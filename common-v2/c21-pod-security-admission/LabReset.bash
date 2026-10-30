#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The candidate's Pod first, then any probe the grader left behind, then the
# namespace itself - deleting the namespace is what takes back the
# pod-security labels they added.
# --ignore-not-found everywhere, so running the reset twice is harmless.
k delete pod compliant -n psa-test --ignore-not-found --timeout=60s >/dev/null 2>&1
k delete pod psa-violation-probe -n psa-test --ignore-not-found --timeout=60s >/dev/null 2>&1
k delete namespace psa-test --ignore-not-found --timeout=120s >/dev/null 2>&1

echo "c21 reset: namespace psa-test removed"
