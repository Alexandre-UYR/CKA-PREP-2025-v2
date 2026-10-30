#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the Deployment, the Service the candidate creates, and
# any throwaway pod the validator left behind - deleting it removes all three.
k delete namespace edge --ignore-not-found --timeout=120s >/dev/null

echo "w19 reset: namespace edge removed"
