#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# The namespace holds the Service and the Deployment; deleting it removes
# both.
k delete namespace traps --ignore-not-found --timeout=120s >/dev/null

# The manifest the candidate was asked to save. A file handed to the
# candidate is not removed by deleting the namespace, so remove it by name.
rm -f /root/svc.yaml
[ -n "${HOME:-}" ] && rm -f "$HOME/svc.yaml"
rm -f ./svc.yaml
rm -f /tmp/cka-lab/svc.yaml /tmp/cka-lab/x20.ann.json /tmp/cka-lab/x20.dep.uid

echo "x20 reset: namespace traps removed, the manifest and the state files deleted"
