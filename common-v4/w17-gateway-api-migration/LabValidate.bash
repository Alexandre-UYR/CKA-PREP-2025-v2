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

NS=gw
DEP=web
SVC=web
ING=web
SEC=web-tls
GWCLASS=nginx-class
GATEWAY=web-gateway
ROUTE=web-route
HOST=gateway.web.k8s.local

DIR=/tmp/cka-lab/gateway
UIDFILE="$DIR/pre-state-uid.txt"

echo "== w17: Move the routing to the new API without changing the outside =="

# ---- 1. the Gateway API CRDs ------------------------------------------------

MISSING_CRD=""
for crd in gatewayclasses.gateway.networking.k8s.io gateways.gateway.networking.k8s.io httproutes.gateway.networking.k8s.io; do
  if k get crd "$crd" >/dev/null 2>&1; then
    ok "the CRD $crd is installed"
  else
    bad "the CRD $crd is installed"
    MISSING_CRD="$MISSING_CRD $crd"
  fi
done

if [ -n "$MISSING_CRD" ]; then
  note "the Gateway and the HTTPRoute cannot exist without their CRDs, so the"
  note "object checks below are skipped. Installing the Gateway API CRDs needs"
  note "network access to the release manifest."
  skip "the Gateway checks (the Gateway API CRDs are missing:$MISSING_CRD)"
  skip "the HTTPRoute checks (the Gateway API CRDs are missing:$MISSING_CRD)"
fi

# ---- 2. the Gateway ---------------------------------------------------------

if [ -n "$MISSING_CRD" ]; then
  :
elif ! k get gateway "$GATEWAY" -n "$NS" >/dev/null 2>&1; then
  bad "Gateway $GATEWAY exists in namespace $NS"
  skip "the Gateway checks (there is no Gateway $GATEWAY)"
else
  ok "Gateway $GATEWAY exists in namespace $NS"

  GWCLASSNAME=$(k -n "$NS" get gateway "$GATEWAY" -o jsonpath='{.spec.gatewayClassName}' 2>/dev/null)
  eq "the Gateway uses the gateway class $GWCLASS" "${GWCLASSNAME:-}" "$GWCLASS"

  # One line per listener: protocol::port::hostname::tls mode::certificate refs
  LIST=$(k -n "$NS" get gateway "$GATEWAY" \
    -o jsonpath='{range .spec.listeners[*]}{.protocol}{"::"}{.port}{"::"}{.hostname}{"::"}{.tls.mode}{"::"}{.tls.certificateRefs[*].name}{"\n"}{end}' 2>/dev/null)

  has "the Gateway has an HTTPS listener on port 443" "$LIST" "HTTPS::443::"
  has "the HTTPS listener listens for the host $HOST" "$LIST" "HTTPS::443::$HOST::"
  has "the HTTPS listener terminates TLS" "$LIST" "HTTPS::443::$HOST::Terminate::"
  has "the HTTPS listener uses the certificate secret $SEC" "$LIST" "HTTPS::443::$HOST::Terminate::$SEC"

  if [ -z "$LIST" ]; then
    note "the Gateway has no listeners, or they could not be read"
  else
    note "the listeners of the Gateway, as protocol::port::hostname::tls mode::certificate:"
    printf '%s\n' "$LIST" | sed 's/^/        /'
  fi
fi

# ---- 3. the HTTPRoute -------------------------------------------------------

if [ -n "$MISSING_CRD" ]; then
  :
elif ! k get httproute "$ROUTE" -n "$NS" >/dev/null 2>&1; then
  bad "HTTPRoute $ROUTE exists in namespace $NS"
  skip "the HTTPRoute checks (there is no HTTPRoute $ROUTE)"
else
  ok "HTTPRoute $ROUTE exists in namespace $NS"

  HOSTNAMES=$(k -n "$NS" get httproute "$ROUTE" -o jsonpath='{.spec.hostnames[*]}' 2>/dev/null)
  has "the HTTPRoute serves the host $HOST" "$HOSTNAMES" "$HOST"

  PARENTS=$(k -n "$NS" get httproute "$ROUTE" -o jsonpath='{.spec.parentRefs[*].name}' 2>/dev/null)
  has "the HTTPRoute belongs to the Gateway $GATEWAY" "$PARENTS" "$GATEWAY"

  MATCH=$(k -n "$NS" get httproute "$ROUTE" \
    -o jsonpath='{range .spec.rules[*].matches[*]}{.path.type}{"::"}{.path.value}{"\n"}{end}' 2>/dev/null)
  has "the HTTPRoute matches the path prefix /" "$MATCH" "PathPrefix::/"

  BACKEND=$(k -n "$NS" get httproute "$ROUTE" \
    -o jsonpath='{range .spec.rules[*].backendRefs[*]}{.name}{"::"}{.port}{"\n"}{end}' 2>/dev/null)
  has "the HTTPRoute sends the traffic to the Service $SVC on port 80" "$BACKEND" "$SVC::80"
fi

# ---- 4. the Ingress has to go -----------------------------------------------

if k -n "$NS" get ingress "$ING" >/dev/null 2>&1; then
  bad "the Ingress $ING no longer exists (it is still in namespace $NS)"
  CUR=$(k -n "$NS" get ingress "$ING" -o jsonpath='{.metadata.uid}' 2>/dev/null)
  REC=$(grep "^ingress/$ING " "$UIDFILE" 2>/dev/null | awk '{print $2}')
  if [ -n "$REC" ] && [ "$CUR" = "$REC" ]; then
    note "it is still the original Ingress - it has to be deleted, not edited"
  fi
  note "the hostname would be claimed by two objects at once"
else
  ok "the Ingress $ING no longer exists"
fi

# ---- the Service and the Deployment are left alone --------------------------

exists "Deployment $DEP exists in namespace $NS" -n "$NS" deploy "$DEP"
exists "Service $SVC exists in namespace $NS" -n "$NS" svc "$SVC"

if [ -f "$UIDFILE" ]; then
  RECDEP=$(grep "^deployment/$DEP " "$UIDFILE" 2>/dev/null | awk '{print $2}')
  CURDEP=$(k -n "$NS" get deployment "$DEP" -o jsonpath='{.metadata.uid}' 2>/dev/null)
  if [ -n "$RECDEP" ]; then
    eq "the Deployment $DEP is the one the setup created (it was not recreated)" "$CURDEP" "$RECDEP"
  else
    skip "the Deployment identity check (the setup did not record it)"
  fi

  RECSVC=$(grep "^service/$SVC " "$UIDFILE" 2>/dev/null | awk '{print $2}')
  CURSVC=$(k -n "$NS" get service "$SVC" -o jsonpath='{.metadata.uid}' 2>/dev/null)
  if [ -n "$RECSVC" ]; then
    eq "the Service $SVC is the one the setup created (it was not recreated)" "$CURSVC" "$RECSVC"
  else
    skip "the Service identity check (the setup did not record it)"
  fi
else
  skip "the identity checks (there is no $UIDFILE - was the setup run?)"
fi

REP=$(k -n "$NS" get deployment "$DEP" -o jsonpath='{.spec.replicas}' 2>/dev/null)
eq "the Deployment $DEP still asks for 1 replica" "${REP:-}" "1"

IMG=$(k -n "$NS" get deployment "$DEP" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
eq "the Deployment $DEP still runs nginx:1.25" "${IMG:-}" "nginx:1.25"

SPORT=$(k -n "$NS" get service "$SVC" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
eq "the Service $SVC still serves port 80" "${SPORT:-}" "80"

exists "the Secret $SEC still exists in namespace $NS" -n "$NS" secret "$SEC"

note "In the Ingress, TLS lives in a spec.tls block that lists the hosts and"
note "the secret. In the Gateway API, TLS lives on the LISTENER, and each"
note "listener has one hostname."
note "The Certificate the Ingress referred to becomes a certificateRef - the"
note "same Secret, named the same way, so the certificate served is unchanged."
note "Leaving the Ingress in place would mean two objects claiming the same"
note "hostname."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}w17 PASSED${X}"; else echo -e "${R}w17 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
