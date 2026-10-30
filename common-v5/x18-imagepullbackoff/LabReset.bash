#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the Pod and the ConfigMap; deleting it removes both.
k delete namespace reg --ignore-not-found --timeout=120s >/dev/null

# Remove the copy of the ConfigMap taken at setup.
rm -f /tmp/cka-lab/x18.cm.data

echo "x18 reset: namespace reg removed, the ConfigMap copy deleted"
