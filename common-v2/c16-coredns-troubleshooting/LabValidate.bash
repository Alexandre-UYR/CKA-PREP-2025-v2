#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }
G='\033[32m'; R='\033[31m'; X='\033[0m'
FAILS=0
ok(){ echo -e "${G}PASS${X}  $1"; }
bad(){ echo -e "${R}FAIL${X}  $1"; FAILS=$((FAILS+1)); }
eq(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }
has(){ case "$2" in *"$3"*) ok "$1";; *) bad "$1 (got '$2')";; esac; }
nonempty(){ if [ -n "$2" ]; then ok "$1"; else bad "$1"; fi; }
exists(){ local d=$1; shift; if k get "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
note(){ echo -e "      NOTE  $1"; }
skip(){ echo -e "      SKIP  $1"; }

NS=dns
NS_SYS=kube-system
CM=coredns
DEP=coredns
BROKEN=kubernetesBROKEN
NAME=kubernetes.default.svc.cluster.local
PROBE=dnsprobe

echo "== c16: Cluster DNS has stopped working =="

if ! exists "namespace $NS exists" namespace "$NS"; then
  echo; echo -e "${R}c16 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the Corefile has to be parseable and has to keep the kubernetes plugin ----
COREFILE=$(k -n "$NS_SYS" get configmap "$CM" -o jsonpath='{.data.Corefile}' 2>/dev/null)
if [ -n "$COREFILE" ]; then
  ok "the CoreDNS ConfigMap $CM has a Corefile"
else
  bad "the CoreDNS ConfigMap $CM has a Corefile (got nothing)"
fi

case "$COREFILE" in
  *"$BROKEN"*) bad "the Corefile does not contain the broken plugin name '$BROKEN'";;
  *) ok "the Corefile does not contain the broken plugin name '$BROKEN'";;
esac

case "$COREFILE" in
  *"kubernetes"*) ok "the Corefile contains the kubernetes plugin";;
  *) bad "the Corefile contains the kubernetes plugin (got '$(printf '%s' "$COREFILE" | tr '\n' ' ')')";;
esac

# ---- the CoreDNS pods have to come back ----
# A pod in CrashLoopBackOff backs off for minutes, so give them time to be
# recreated and become ready after the ConfigMap was fixed.
i=0
READY=""
while [ $i -lt 75 ]; do
  READY=$(k -n "$NS_SYS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  case "$READY" in ''|*[!0-9]*) READY=0;; esac
  [ "$READY" -ge 1 ] && break
  i=$((i+1)); sleep 2
done
if [ "${READY:-0}" -ge 1 ]; then
  ok "the CoreDNS Deployment has at least 1 ready replica"
else
  bad "the CoreDNS Deployment has at least 1 ready replica (got '${READY:-0}') - the pods may still be running the old Corefile, restart them with 'kubectl -n $NS_SYS rollout restart deploy/$DEP'"
fi

# ---- live test: does a pod resolve a cluster service name? ----
DNS_OUT=""
DNS_PHASE=""
k -n "$NS" delete pod "$PROBE" --ignore-not-found --wait=false >/dev/null 2>&1
k -n "$NS" run "$PROBE" --restart=Never --image=busybox:1.36 -- \
  nslookup "$NAME" >/dev/null 2>&1
i=0
while [ $i -lt 60 ]; do
  DNS_PHASE=$(k -n "$NS" get pod "$PROBE" -o jsonpath='{.status.phase}' 2>/dev/null)
  case "$DNS_PHASE" in Succeeded|Failed) break;; esac
  i=$((i+1)); sleep 2
done
DNS_OUT=$(k -n "$NS" logs "$PROBE" 2>/dev/null)
k -n "$NS" delete pod "$PROBE" --ignore-not-found --wait=false >/dev/null 2>&1

# The answer line is "Address: 10.96.0.1". The resolver's own line is
# "Address: 10.96.0.10:53", which carries a port and does not match.
ADDR=$(printf '%s\n' "$DNS_OUT" \
  | grep -E '^Address:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*$' \
  | tail -n 1 | tr -d ' \t')

if [ -n "$ADDR" ]; then
  ok "a pod in namespace $NS resolves $NAME (address $ADDR)"
elif printf '%s' "$DNS_OUT" | grep -qi "can't find\|NXDOMAIN\|SERVFAIL\|no servers"; then
  bad "a pod in namespace $NS resolves $NAME (nslookup reported a failure: '$(printf '%s' "$DNS_OUT" | tr '\n' ' | ')')"
elif [ -z "$DNS_OUT" ]; then
  bad "a pod in namespace $NS resolves $NAME (the probe pod produced no output - phase '$DNS_PHASE', so the probe could not run)"
else
  bad "a pod in namespace $NS resolves $NAME (no address in the nslookup output: '$(printf '%s' "$DNS_OUT" | tr '\n' ' | ')')"
fi

note "The kubernetes plugin is the one that serves cluster service names."
note "External names go through 'forward . /etc/resolv.conf' instead."
note "CoreDNS reads its Corefile at start-up: editing the ConfigMap is not"
note "enough, the Deployment has to be restarted to pick the change up."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c16 PASSED${X}"; else echo -e "${R}c16 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
