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

NS=netpol
FNS=frontend
HTTPD=my-httpd
PROXY=my-proxy
APP=my-app
CLIENT=client

echo "== x12: One door open, one door shut =="

POLS=$(k -n "$NS" get networkpolicy -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)
COUNT=$(printf '%s\n' "$POLS" | sed '/^$/d' | wc -l | tr -d ' ')
if [ "${COUNT:-0}" -ge 2 ]; then
  ok "two NetworkPolicies exist in namespace $NS ($COUNT of them)"
else
  bad "two NetworkPolicies exist in namespace $NS (found ${COUNT:-0})"
fi

# ---------------------------------------------------------------------------
# The policy that opens the door, and only that door
# ---------------------------------------------------------------------------
HTTPD_POL=""
PROXY_POL=""
MYAPP_POL=""
for p in $POLS; do
  SEL=$(k -n "$NS" get networkpolicy "$p" -o jsonpath='{.spec.podSelector.matchLabels.app}' 2>/dev/null)
  case "$SEL" in
    httpd)  [ -z "$HTTPD_POL" ] && HTTPD_POL="$p";;
    proxy)  [ -z "$PROXY_POL" ] && PROXY_POL="$p";;
    myapp)  [ -z "$MYAPP_POL" ] && MYAPP_POL="$p";;
  esac
done

if [ -z "$HTTPD_POL" ]; then
  bad "a NetworkPolicy selects the $HTTPD Pods (app=httpd)"
else
  ok "a NetworkPolicy selects the $HTTPD Pods (app=httpd): $HTTPD_POL"

  FROM=$(k -n "$NS" get networkpolicy "$HTTPD_POL" \
           -o jsonpath='{range .spec.ingress[*].from[*]}{.podSelector.matchLabels}{"\n"}{end}' 2>/dev/null)
  if printf '%s\n' "$FROM" | grep -q 'httpd-access:true'; then
    ok "the ingress rule allows pods labelled httpd-access=true"
  else
    bad "the ingress rule allows pods labelled httpd-access=true (found: $(printf '%s' "$FROM" | tr '\n' ' '))"
  fi

  # ...and nobody else. A rule with no 'from' at all allows every source.
  ALLOWS_ALL=0
  i=0
  while [ "$i" -lt 10 ]; do
    RULE=$(k -n "$NS" get networkpolicy "$HTTPD_POL" -o jsonpath="{.spec.ingress[$i]}" 2>/dev/null)
    [ -z "$RULE" ] && break
    F=$(k -n "$NS" get networkpolicy "$HTTPD_POL" -o jsonpath="{.spec.ingress[$i].from}" 2>/dev/null)
    if [ -z "$F" ]; then
      ALLOWS_ALL=1
      break
    fi
    i=$((i+1))
  done
  NPJ=$(k -n "$NS" get networkpolicy "$HTTPD_POL" -o json 2>/dev/null | tr -d ' \t\n')
  case "$NPJ" in
    *'"namespaceSelector":{}'*) ALLOWS_ALL=1;;
  esac
  case "$NPJ" in
    *'"0.0.0.0/0"'*) ALLOWS_ALL=1;;
  esac
  if [ "$ALLOWS_ALL" -eq 1 ]; then
    bad "the policy allows nobody else in (it has a rule that admits every source)"
  else
    ok "the policy allows nobody else in (no rule admits every source)"
  fi
fi

# ---------------------------------------------------------------------------
# The policy that shuts the other door
# ---------------------------------------------------------------------------
DENY_OK=0
if [ -n "$PROXY_POL" ]; then
  ING=$(k -n "$NS" get networkpolicy "$PROXY_POL" -o jsonpath='{.spec.ingress}' 2>/dev/null)
  PT=$(k -n "$NS" get networkpolicy "$PROXY_POL" -o jsonpath='{.spec.policyTypes}' 2>/dev/null)
  if [ -z "$ING" ] || [ "$ING" = "[]" ]; then
    if [ -z "$PT" ] || printf '%s' "$PT" | grep -q 'Ingress'; then
      ok "a NetworkPolicy selects the $PROXY Pods (app=proxy) and lists no ingress rule, so nothing can reach them"
      DENY_OK=1
    else
      bad "a NetworkPolicy selects the $PROXY Pods (app=proxy) and lists no ingress rule, so nothing can reach them (its policyTypes are '$PT')"
    fi
  else
    bad "a NetworkPolicy selects the $PROXY Pods (app=proxy) and lists no ingress rule, so nothing can reach them (it lists: $ING)"
  fi
fi

# The same outcome, written the other way round: an egress policy on my-app
# that does not let it reach the proxy.
if [ "$DENY_OK" -eq 0 ] && [ -n "$MYAPP_POL" ]; then
  EGR=$(k -n "$NS" get networkpolicy "$MYAPP_POL" -o jsonpath='{.spec.egress}' 2>/dev/null)
  TO=$(k -n "$NS" get networkpolicy "$MYAPP_POL" \
        -o jsonpath='{range .spec.egress[*].to[*]}{.podSelector.matchLabels}{"\n"}{end}' 2>/dev/null)
  if { [ -z "$EGR" ] || [ "$EGR" = "[]" ]; } && ! printf '%s\n' "$TO" | grep -q 'app:proxy'; then
    ok "a NetworkPolicy selects the $APP Pods (app=myapp) and its egress rules do not let them reach the proxy"
    DENY_OK=1
  else
    note "a policy selects app=myapp, but its egress rules still let it reach the proxy"
  fi
fi

if [ "$DENY_OK" -eq 0 ]; then
  bad "a NetworkPolicy keeps $APP away from $PROXY (no policy isolates the proxy, and none of the egress policies stops my-app)"
fi

# ---------------------------------------------------------------------------
# Live: the labelled client gets in, my-app stays out
# ---------------------------------------------------------------------------
PROBE="$CLIENT"
PROBE_OWNED=0
if ! k -n "$FNS" get pod "$CLIENT" >/dev/null 2>&1; then
  # The client is gone. Make a Pod of our own with the same label, in the
  # same namespace, so that the probe still says something.
  PROBE=x12-probe
  PROBE_OWNED=1
  k -n "$FNS" delete pod "$PROBE" --ignore-not-found >/dev/null 2>&1
  cat <<EOF | k apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: $PROBE
  namespace: $FNS
  labels:
    httpd-access: "true"
spec:
  containers:
    - name: probe
      image: curlimages/curl
      command: ["sleep", "3600"]
EOF
  i=0
  while [ "$i" -lt 60 ]; do
    R=$(k -n "$FNS" get pod "$PROBE" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
    [ "$R" = "true" ] && break
    sleep 2
    i=$((i+2))
  done
  note "the client Pod was missing, so a Pod labelled httpd-access=true was created in namespace $FNS for the probe"
fi

CODE=$(k -n "$FNS" exec "$PROBE" -- curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
         "http://$HTTPD.$NS.svc.cluster.local" 2>/dev/null)
eq "a Pod labelled httpd-access=true reaches $HTTPD on port 80" "$CODE" "200"

if [ "$PROBE_OWNED" -eq 1 ]; then
  k -n "$FNS" delete pod "$PROBE" --ignore-not-found >/dev/null 2>&1
fi

if ! exists "the $APP Pod exists in namespace $NS" -n "$NS" pod "$APP"; then
  skip "the live probe below (there is no $APP Pod in namespace $NS)"
else
  OUT=$(k -n "$NS" exec "$APP" -- wget -S -O - -T 5 "http://$PROXY.$NS.svc.cluster.local" 2>&1)
  if printf '%s' "$OUT" | grep -qiE 'not found|no such file|executable file'; then
    skip "the live probe below (the $APP container has no wget, so the request cannot be made from inside it)"
  elif printf '%s' "$OUT" | grep -qE 'HTTP/1\.[01] 200'; then
    bad "$APP cannot reach $PROXY (it still got HTTP 200) - EITHER the policy is wrong OR this cluster's CNI does not enforce NetworkPolicy"
  else
    ok "$APP cannot reach $PROXY (no HTTP 200 came back)"
  fi
fi

note "A NetworkPolicy that selects a Pod and lists no ingress rules isolates"
note "that Pod completely. The absence of the rules is the deny - it is not a"
note "missing rule that lets everything through."
note ""
note "NetworkPolicy is only enforced if the CNI implements it. On a cluster"
note "whose CNI ignores policies, the negative probe above keeps succeeding"
note "and no policy can make it fail."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}x12 PASSED${X}"; else echo -e "${R}x12 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
