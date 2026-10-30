#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the Deployment and every Service, including the two the
# candidate created; deleting it removes all of them. The annotation that
# recorded the original Service's UID goes with the namespace.
k delete namespace svcs --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# No file is graded in this question, so there is nothing on disk to remove.
# A candidate who wrote notes is free to keep them.

echo "w2 reset: namespace svcs removed (Deployment web and all Services gone)"
