#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

ROOT=/tmp/cka-lab/kustomize

# What the dev overlay put in the cluster. The overlay may have gone into the
# current namespace or into a namespace of its own, so the Deployment is
# looked for wherever it is and removed there.
for ns in $(k get deploy -A -o jsonpath='{range .items[?(@.metadata.name=="app")]}{.metadata.namespace}{" "}{end}' 2>/dev/null || true); do
  k -n "$ns" delete deploy app --ignore-not-found --timeout=60s >/dev/null 2>&1 || true
  k -n "$ns" delete svc   app --ignore-not-found --timeout=60s >/dev/null 2>&1 || true
done

# The candidate's overlays. The base is left in place - the setup rebuilds it
# from scratch anyway.
rm -rf "$ROOT/overlays"

echo "c24 reset: the applied Deployment app and Service app removed, and the"
echo "            overlays directory deleted (the base was left in place)"
