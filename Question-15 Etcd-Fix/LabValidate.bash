#!/bin/bash
set -uo pipefail

G='\033[32m'; R='\033[31m'; X='\033[0m'
FAILS=0
ok(){ echo -e "${G}PASS${X}  $1"; }
bad(){ echo -e "${R}FAIL${X}  $1"; FAILS=$((FAILS+1)); }
eq(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }
has(){ case "$2" in *"$3"*) ok "$1";; *) bad "$1 (got '$2')";; esac; }
nonempty(){ if [ -n "$2" ]; then ok "$1"; else bad "$1"; fi; }
note(){ echo -e "      NOTE  $1"; }

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

MANIFEST=/etc/kubernetes/manifests/kube-apiserver.yaml

echo "== Q15 etcd fix =="

# ---- the manifest no longer points at the peer port ----
if $SUDO grep -q 'etcd-servers=https://127.0.0.1:2380' "$MANIFEST" 2>/dev/null; then
  bad "the apiserver still points at the etcd PEER port 2380"
else
  ok "the apiserver no longer points at the etcd peer port 2380"
fi

# ---- it points back at the client port ----
ENDPOINT=$($SUDO grep -o 'etcd-servers=[^ ]*' "$MANIFEST" 2>/dev/null | head -1 | tr -d '"')
eq "the apiserver's etcd endpoint is the client port 2379" "$ENDPOINT" "etcd-servers=https://127.0.0.1:2379"

# ---- the static pod is running again ----
STATE=""
if command -v crictl >/dev/null 2>&1 || [ -x /usr/bin/crictl ]; then
  STATE=$($SUDO crictl ps --name kube-apiserver --state Running -q 2>/dev/null | head -1)
  if [ -z "$STATE" ]; then
    STATE=$($SUDO crictl ps 2>/dev/null | grep kube-apiserver | awk '{print $1}' | head -1)
  fi
fi
if [ -n "$STATE" ]; then
  ok "the kube-apiserver static pod is running again"
else
  bad "the kube-apiserver static pod is not running"
fi

# ---- and the API server actually answers ----
echo "Waiting for the API server to come back..."
API=no
for i in $(seq 1 30); do
  if kubectl get nodes --request-timeout=5s >/dev/null 2>&1; then API=yes; break; fi
  sleep 4
done
eq "kubectl can reach the API server again" "$API" "yes"

if [ "$API" = "yes" ]; then
  NODES=$(kubectl get nodes --no-headers --request-timeout=10s 2>/dev/null | wc -l | tr -d ' ')
  nonempty "the cluster reports its nodes" "$NODES"
fi

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}Q15 PASSED${X}"; else echo -e "${R}Q15 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
