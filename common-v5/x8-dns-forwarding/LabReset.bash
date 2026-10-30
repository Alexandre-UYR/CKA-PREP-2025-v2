#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

NS=dns
NS_SYS=kube-system
LABDIR=/tmp/cka-lab
ORIG_CF="$LABDIR/x8.corefile"
BROKEN_CF="$LABDIR/x8.corefile.broken"

# The namespace holds the verification pods and the candidate's own pods.
k delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# Put the CoreDNS ConfigMap back the way the setup found it. The saved
# Corefile is used rather than the saved ConfigMap, because a saved
# ConfigMap carries a stale resourceVersion and would be rejected.
CM_NAME="coredns"
k -n "$NS_SYS" get configmap "$CM_NAME" >/dev/null 2>&1 || \
  CM_NAME=$(k -n "$NS_SYS" get configmap -l k8s-app=kube-dns -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
DEP_NAME="coredns"
k -n "$NS_SYS" get deployment "$DEP_NAME" >/dev/null 2>&1 || \
  DEP_NAME=$(k -n "$NS_SYS" get deployment -l k8s-app=kube-dns -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [ -s "$ORIG_CF" ]; then
  k -n "$NS_SYS" create configmap "$CM_NAME" --from-file=Corefile="$ORIG_CF" \
    --dry-run=client -o yaml | k apply -f - >/dev/null 2>&1 || true
  k -n "$NS_SYS" rollout restart "deploy/$DEP_NAME" >/dev/null 2>&1 || true
  k -n "$NS_SYS" rollout status "deploy/$DEP_NAME" --timeout=180s >/dev/null 2>&1 || true
  RESTORED=yes
else
  RESTORED=no
fi

# The state files. The saved original Corefile goes too: the next run of the
# setup saves a fresh copy of whatever the ConfigMap holds at that moment.
rm -f "$ORIG_CF" "$BROKEN_CF"

echo "x8 reset: namespace $NS removed, the CoreDNS ConfigMap $CM_NAME restored"
echo "          from the saved Corefile ($RESTORED), CoreDNS restarted, and the"
echo "          state files under $LABDIR deleted"
