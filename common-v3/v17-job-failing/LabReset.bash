#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the Job, the Job's pods, and any replacement Job the
# candidate created. Deleting it takes all of them - a Job does not keep
# anything outside its namespace.
k delete namespace jobs --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

echo "v17 reset: namespace jobs removed"
