#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the Pod and its emptyDir, so deleting it removes both.
k delete namespace shared --ignore-not-found --timeout=120s >/dev/null

echo "w20 reset: namespace shared removed"
