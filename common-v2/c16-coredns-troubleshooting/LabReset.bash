#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }
LAB_DIR=/tmp/cka-lab
CM_BACKUP="$LAB_DIR/c16.coredns.cm"
CF_BACKUP="$LAB_DIR/c16.corefile"
BROKEN_CF="$LAB_DIR/c16.corefile.broken"
NS=dns
NS_SYS=kube-system
CM=coredns
DEP=coredns

# The probe pod the candidate left behind, and the namespace itself.
k -n "$NS" delete pod dnsprobe --ignore-not-found --wait=false >/dev/null 2>&1 || true
k delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# Put the CoreDNS ConfigMap back the way the setup found it. The saved
# Corefile is used rather than the saved ConfigMap, because the saved
# ConfigMap carries a stale resourceVersion and would be rejected.
if [ -s "$CF_BACKUP" ]; then
  k -n "$NS_SYS" create configmap "$CM" --from-file=Corefile="$CF_BACKUP" \
    --dry-run=client -o yaml | k apply -f - >/dev/null 2>&1 || true
  k -n "$NS_SYS" rollout restart "deploy/$DEP" >/dev/null 2>&1 || true
  k -n "$NS_SYS" rollout status "deploy/$DEP" --timeout=120s >/dev/null 2>&1 || true
fi

# The broken Corefile copy is ours, so it goes. The saved original is kept:
# the setup needs it to restore the cluster, and it is the only copy.
rm -f "$BROKEN_CF"

echo "c16 reset: namespace dns removed, CoreDNS ConfigMap restored from $CF_BACKUP"
