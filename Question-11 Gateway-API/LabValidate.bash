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

echo "== Q11 Gateway API =="

HOST=gateway.web.k8s.local

# ---- the Gateway ----
if ! exists "Gateway web-gateway exists" gateway web-gateway; then
  echo
  echo -e "${R}Q11 FAILED ($FAILS checks)${X}"; exit 1
fi

eq "Gateway web-gateway uses gatewayClassName nginx-class" \
  "$(k get gateway web-gateway -o jsonpath='{.spec.gatewayClassName}' 2>/dev/null)" "nginx-class"

# The listener that serves the migrated host.
LPROTO=$(k get gateway web-gateway -o jsonpath="{.spec.listeners[?(@.hostname==\"$HOST\")].protocol}" 2>/dev/null)
eq "Gateway web-gateway has a listener for $HOST with protocol HTTPS" "$LPROTO" "HTTPS"

LPORT=$(k get gateway web-gateway -o jsonpath="{.spec.listeners[?(@.hostname==\"$HOST\")].port}" 2>/dev/null)
eq "Gateway web-gateway has a listener for $HOST on port 443" "$LPORT" "443"

LMODE=$(k get gateway web-gateway -o jsonpath="{.spec.listeners[?(@.hostname==\"$HOST\")].tls.mode}" 2>/dev/null)
eq "the $HOST listener terminates TLS (tls.mode Terminate)" "$LMODE" "Terminate"

LREFS=$(k get gateway web-gateway -o jsonpath="{.spec.listeners[?(@.hostname==\"$HOST\")].tls.certificateRefs[*].name}" 2>/dev/null)
has "the $HOST listener's certificateRefs reference the secret web-tls" "$LREFS" "web-tls"

LKIND=$(k get gateway web-gateway -o jsonpath="{.spec.listeners[?(@.hostname==\"$HOST\")].tls.certificateRefs[?(@.name==\"web-tls\")].kind}" 2>/dev/null)
if [ "$LKIND" = "Secret" ] || [ -z "$LKIND" ]; then
  ok "the certificateRef to web-tls has kind Secret${LKIND:+ (explicit)}"
else
  bad "the certificateRef to web-tls has kind '$LKIND', want 'Secret'"
fi

# ---- the HTTPRoute ----
if ! exists "HTTPRoute web-route exists" httproute web-route; then
  echo
  echo -e "${R}Q11 FAILED ($FAILS checks)${X}"; exit 1
fi

RHOSTS=$(k get httproute web-route -o jsonpath='{.spec.hostnames[*]}' 2>/dev/null)
has "HTTPRoute web-route serves hostname $HOST" "$RHOSTS" "$HOST"

RPARENTS=$(k get httproute web-route -o jsonpath='{.spec.parentRefs[*].name}' 2>/dev/null)
has "HTTPRoute web-route attaches to the Gateway web-gateway" "$RPARENTS" "web-gateway"

RMATCH=$(k get httproute web-route -o jsonpath='{.spec.rules[*].matches[?(@.path.type=="PathPrefix" && @.path.value=="/")].path.value}' 2>/dev/null)
has "HTTPRoute web-route has a rule matching path / with type PathPrefix" "$RMATCH" "/"

RBACK=$(k get httproute web-route -o jsonpath='{.spec.rules[*].backendRefs[?(@.name=="web-service" && @.port==80)].port}' 2>/dev/null)
has "HTTPRoute web-route sends traffic to web-service on port 80" "$RBACK" "80"

# ---- the source objects must survive: this is a MIGRATION, not a move ----
exists "the source Ingress web still exists" ingress web
exists "the source Secret web-tls still exists" secret web-tls

ISINGTLS=$(k get ingress web -o jsonpath='{.spec.tls[0].secretName}' 2>/dev/null)
eq "the source Ingress web still terminates TLS with the secret web-tls" "$ISINGTLS" "web-tls"

CRT=$(k get secret web-tls -o jsonpath='{.data.tls\.crt}' 2>/dev/null)
SUBJ=$(printf '%s' "$CRT" | base64 -d 2>/dev/null | openssl x509 -noout -subject 2>/dev/null)
has "the web-tls certificate's CN is $HOST" "$SUBJ" "$HOST"

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}Q11 PASSED${X}"; else echo -e "${R}Q11 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
