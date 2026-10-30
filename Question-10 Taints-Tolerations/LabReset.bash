#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# Remove the taint from every node - the candidate may have tainted a different
# one from the one the setup recorded.
for n in $(k get nodes -o name 2>/dev/null); do
  k taint "$n" PERMISSION- >/dev/null 2>&1 || true
done

# Delete the pods that were created for this lab. A pod counts as ours if it
# carries a toleration for the PERMISSION key, or if it is one of the names the
# reference solution uses.
for ns in $(k get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' 2>/dev/null | sort -u); do
  [ -n "$ns" ] || continue
  for p in $(k get pods -n "$ns" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.tolerations[*].key}{"\n"}{end}' 2>/dev/null \
      | awk '$2 ~ /PERMISSION/ {print $1}'); do
    k delete pod -n "$ns" "$p" --ignore-not-found >/dev/null 2>&1 || true
  done
  k delete pod -n "$ns" nginx nginx-fail --ignore-not-found >/dev/null 2>&1 || true
done

rm -f /tmp/cka-lab/q10.nodes

echo "Q10 reset"
