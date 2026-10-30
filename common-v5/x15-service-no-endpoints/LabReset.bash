#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the Deployment, its pods and the Service, so deleting it
# removes everything the setup created and everything the candidate produced.
k delete namespace shop --ignore-not-found --timeout=120s >/dev/null

rm -f /tmp/cka-lab/x15.svc.uid

echo "x15 reset: namespace shop removed (Deployment, pods and Service), the state file deleted"
