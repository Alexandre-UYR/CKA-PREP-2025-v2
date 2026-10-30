#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the Deployment and the Service the candidate creates, so
# deleting it removes both and leaves nothing for the next attempt to trip over.
k delete namespace web --ignore-not-found --timeout=120s >/dev/null

echo "w18 reset: namespace web removed"
