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

NS=pol
CLI=client
OTH=other
DEP=api
POL=api
URL="http://$DEP.$NS.svc.cluster.local"

echo "== v12: Open the door, but only that door =="

if ! exists "NetworkPolicy $POL exists in namespace $NS" -n "$NS" networkpolicy "$POL"; then
  echo; echo -e "${R}v12 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the policy selects the api pods, and covers both directions ----
SEL=$(k -n "$NS" get networkpolicy "$POL" -o jsonpath='{.spec.podSelector.matchLabels.app}' 2>/dev/null)
eq "the podSelector selects app=$DEP" "$SEL" "$DEP"

PT=$(k -n "$NS" get networkpolicy "$POL" -o jsonpath='{.spec.policyTypes}' 2>/dev/null | tr -d '\n')
has "policyTypes includes Ingress" "$PT" "Ingress"
has "policyTypes includes Egress" "$PT" "Egress"

# ---- ingress: only from the client namespace, only TCP 80 ----
FROMSEL=$(k -n "$NS" get networkpolicy "$POL" \
  -o jsonpath='{.spec.ingress[*].from[*].namespaceSelector.matchLabels}' 2>/dev/null)
has "the ingress rule allows traffic from the namespace labelled name=client" "$FROMSEL" "client"

INGP=$(k -n "$NS" get networkpolicy "$POL" \
  -o jsonpath='{range .spec.ingress[*].ports[*]}{.protocol}{"/"}{.port}{"\n"}{end}' 2>/dev/null \
  | tr '[:lower:]' '[:upper:]')
if [ -n "$INGP" ]; then
  case "$INGP" in
    *"TCP/80"*|*"TCP/HTTP"*) ok "the ingress rule is restricted to TCP port 80";;
    *) bad "the ingress rule is restricted to TCP port 80 (got '$INGP')";;
  esac
else
  bad "the ingress rule is restricted to TCP port 80 (the rule lists no ports, so it allows every port)"
fi

# ---- egress: DNS only ----
EGP=$(k -n "$NS" get networkpolicy "$POL" \
  -o jsonpath='{range .spec.egress[*].ports[*]}{.protocol}{"/"}{.port}{"\n"}{end}' 2>/dev/null \
  | tr '[:lower:]' '[:upper:]')
nonempty "the policy has egress rules" "$EGP"
has "egress allows DNS over UDP 53" "$EGP" "UDP/53"
has "egress allows DNS over TCP 53" "$EGP" "TCP/53"

# ---- nothing in the policy opens the door wider than it should ----
NPJ=$(k -n "$NS" get networkpolicy "$POL" -o json 2>/dev/null | tr -d ' \t\n')
case "$NPJ" in
  *"0.0.0.0/0"*) bad "there is no unrestricted egress rule (the policy contains ipBlock 0.0.0.0/0)";;
  *) ok "there is no unrestricted egress rule (no ipBlock 0.0.0.0/0)";;
esac
case "$NPJ" in
  *'"to":[]'*) bad "there is no empty egress destination (the policy contains an empty to: [])";;
  *) ok "there is no empty egress destination (no empty to: [])";;
esac
case "$NPJ" in
  *'"namespaceSelector":{}'*) bad "the ingress rule does not allow every namespace (the policy contains an empty namespaceSelector: {})";;
  *) ok "the ingress rule does not allow every namespace (no empty namespaceSelector: {})";;
esac

# ---- the api pod, which the DNS probe runs in ----
APIPOD=$(k -n "$NS" get pods -l "app=$DEP" --field-selector=status.phase=Running \
         -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$APIPOD" ]; then
  bad "a Running api pod exists in namespace $NS"
  skip "the live probes below (no running api pod)"
  echo
  if [ "$FAILS" -eq 0 ]; then echo -e "${G}v12 PASSED${X}"; else echo -e "${R}v12 FAILED ($FAILS checks)${X}"; fi
  exit $(( FAILS > 0 ))
fi
ok "the api pod is $APIPOD"

# ---- live: the client namespace gets in ----
CLIPOD=$(k -n "$CLI" get pods -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$CLIPOD" ]; then
  bad "the probe pod in namespace $CLI exists"
else
  CODE=$(k -n "$CLI" exec "$CLIPOD" -- curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$URL" 2>/dev/null)
  eq "a pod in namespace $CLI reaches $DEP.$NS.svc.cluster.local over HTTP" "$CODE" "200"
fi

# ---- live: the other namespace does not ----
OTHPOD=$(k -n "$OTH" get pods -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$OTHPOD" ]; then
  bad "the probe pod in namespace $OTH exists"
else
  CODE2=$(k -n "$OTH" exec "$OTHPOD" -- curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$URL" 2>/dev/null)
  if [ "$CODE2" = "200" ]; then
    bad "a pod in namespace $OTH is blocked from $DEP.$NS.svc.cluster.local (it still got HTTP 200) - EITHER the policy is wrong OR this cluster's CNI does not enforce NetworkPolicy"
  else
    ok "a pod in namespace $OTH is blocked from $DEP.$NS.svc.cluster.local (got HTTP '${CODE2:-no response}')"
  fi
fi

# ---- live: the api can still resolve names ----
DNSOUT=$(k -n "$NS" exec "$APIPOD" -- sh -c 'nslookup kubernetes.default.svc.cluster.local' 2>&1)
DNSRC=$?
if [ "$DNSRC" -ne 0 ] && printf '%s' "$DNSOUT" | grep -qi 'not found'; then
  # nslookup is not in this image - fall back to getent, which resolves too.
  DNSOUT=$(k -n "$NS" exec "$APIPOD" -- sh -c 'getent hosts kubernetes.default.svc.cluster.local' 2>&1)
  DNSRC=$?
fi
if [ "$DNSRC" -eq 0 ] && ! printf '%s' "$DNSOUT" | grep -qiE 'nxdomain|can.t find|no answer|no servers'; then
  ok "the api pod can still resolve names (DNS works from namespace $NS)"
else
  bad "the api pod can no longer resolve names from namespace $NS (DNS is broken) - the egress rules must allow UDP and TCP port 53"
fi

note "Selecting a pod in a policy that has an ingress rule also isolates that pod's"
note "egress. Once the policy selects the api pods, the only outbound traffic they"
note "are allowed is what the egress rules say - and DNS has to be in there."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}v12 PASSED${X}"; else echo -e "${R}v12 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
