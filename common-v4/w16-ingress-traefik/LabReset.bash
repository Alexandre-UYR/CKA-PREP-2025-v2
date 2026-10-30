#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

TRAEFIK_NS=traefik

# Take the release down properly first, so helm does not leave anything behind
# that it thinks it owns. Any release in the namespace goes, whatever it is
# called.
if command -v helm >/dev/null 2>&1; then
  for r in $(helm list -n "$TRAEFIK_NS" --all -q 2>/dev/null); do
    helm uninstall "$r" -n "$TRAEFIK_NS" >/dev/null 2>&1 || true
  done
fi

# The namespaces hold everything else: the Ingress, the third page, its
# Service, its ConfigMap and the probe pod.
k delete namespace "$TRAEFIK_NS" --ignore-not-found --timeout=120s >/dev/null
k delete namespace web --ignore-not-found --timeout=120s >/dev/null

echo "w16 reset: the traefik release and namespace traefik removed, namespace web removed"
