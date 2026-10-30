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

NS=ing
DEP=api
ING=web

echo "== v13: Two hosts, two certificates =="

if ! exists "Ingress $ING exists in namespace $NS" -n "$NS" ingress "$ING"; then
  echo; echo -e "${R}v13 FAILED ($FAILS checks)${X}"; exit 1
fi

exists "Service $DEP still exists in namespace $NS" -n "$NS" svc "$DEP"

# ---- the ingress class ----
IC=$(k -n "$NS" get ingress "$ING" -o jsonpath='{.spec.ingressClassName}' 2>/dev/null | tr -d '\n')
eq "the Ingress uses ingressClassName nginx" "$IC" "nginx"

# ---- TLS: one entry per host, each naming its own secret ----
TLSMAP=$(k -n "$NS" get ingress "$ING" \
  -o jsonpath='{range .spec.tls[*]}{.secretName}={.hosts[*]}{"\n"}{end}' 2>/dev/null)
TLSN=$(printf '%s\n' "$TLSMAP" | grep -c '.' || true)
eq "the Ingress has exactly two TLS entries" "$TLSN" "2"
has "the TLS entry for api.example.com names the secret api-tls" "$TLSMAP" "api-tls=api.example.com"
has "the TLS entry for alt.example.com names the secret alt-tls" "$TLSMAP" "alt-tls=alt.example.com"

# ---- the rule for api.example.com ----
AH=$(k -n "$NS" get ingress "$ING" \
  -o jsonpath='{range .spec.rules[?(@.host=="api.example.com")]}{.host}{"\n"}{end}' 2>/dev/null | tr -d '\n')
eq "the Ingress has a rule for host api.example.com" "$AH" "api.example.com"

APIP=$(k -n "$NS" get ingress "$ING" \
  -o jsonpath='{range .spec.rules[?(@.host=="api.example.com")].http.paths[*]}{.path}{"\n"}{end}' 2>/dev/null | tr '\n' ' ')
eq "the rule for api.example.com serves the path /api" "$APIP" "/api "

APIT=$(k -n "$NS" get ingress "$ING" \
  -o jsonpath='{range .spec.rules[?(@.host=="api.example.com")].http.paths[*]}{.pathType}{"\n"}{end}' 2>/dev/null | tr '\n' ' ')
eq "the /api path on api.example.com has pathType Prefix" "$APIT" "Prefix "

APIS=$(k -n "$NS" get ingress "$ING" \
  -o jsonpath='{range .spec.rules[?(@.host=="api.example.com")].http.paths[*]}{.backend.service.name}{"\n"}{end}' 2>/dev/null | tr '\n' ' ')
eq "the /api path on api.example.com routes to Service $DEP" "$APIS" "$DEP "

APIN=$(k -n "$NS" get ingress "$ING" \
  -o jsonpath='{range .spec.rules[?(@.host=="api.example.com")].http.paths[*]}{.backend.service.port.number}{"\n"}{end}' 2>/dev/null | tr '\n' ' ')
APINM=$(k -n "$NS" get ingress "$ING" \
  -o jsonpath='{range .spec.rules[?(@.host=="api.example.com")].http.paths[*]}{.backend.service.port.name}{"\n"}{end}' 2>/dev/null | tr '\n' ' ')
SVP=$(k -n "$NS" get svc "$DEP" -o jsonpath='{range .spec.ports[*]}{.name}{"/"}{.port}{"\n"}{end}' 2>/dev/null)
if [ "$APIN" = "80 " ]; then
  ok "the /api path on api.example.com routes to port 80"
elif [ -n "${APINM// /}" ] && [ "${APINM// /}" != "0" ]; then
  case "$SVP" in
    *"${APINM// /}/80"*) ok "the /api path on api.example.com routes to port 80 (the named port ${APINM// /})";;
    *) bad "the /api path on api.example.com routes to port 80 (the named port '${APINM// /}' does not map to 80 on Service $DEP)";;
  esac
else
  bad "the /api path on api.example.com routes to port 80 (got number '$APIN', name '$APINM')"
fi

# ---- the rule for alt.example.com ----
LH=$(k -n "$NS" get ingress "$ING" \
  -o jsonpath='{range .spec.rules[?(@.host=="alt.example.com")]}{.host}{"\n"}{end}' 2>/dev/null | tr -d '\n')
eq "the Ingress has a rule for host alt.example.com" "$LH" "alt.example.com"

ALTP=$(k -n "$NS" get ingress "$ING" \
  -o jsonpath='{range .spec.rules[?(@.host=="alt.example.com")].http.paths[*]}{.path}{"\n"}{end}' 2>/dev/null | tr '\n' ' ')
eq "the rule for alt.example.com serves the path /" "$ALTP" "/ "

ALTPT=$(k -n "$NS" get ingress "$ING" \
  -o jsonpath='{range .spec.rules[?(@.host=="alt.example.com")].http.paths[*]}{.pathType}{"\n"}{end}' 2>/dev/null | tr '\n' ' ')
eq "the / path on alt.example.com has pathType Prefix" "$ALTPT" "Prefix "

ALTS=$(k -n "$NS" get ingress "$ING" \
  -o jsonpath='{range .spec.rules[?(@.host=="alt.example.com")].http.paths[*]}{.backend.service.name}{"\n"}{end}' 2>/dev/null | tr '\n' ' ')
eq "the / path on alt.example.com routes to Service $DEP" "$ALTS" "$DEP "

ALTN=$(k -n "$NS" get ingress "$ING" \
  -o jsonpath='{range .spec.rules[?(@.host=="alt.example.com")].http.paths[*]}{.backend.service.port.number}{"\n"}{end}' 2>/dev/null | tr '\n' ' ')
ALTNM=$(k -n "$NS" get ingress "$ING" \
  -o jsonpath='{range .spec.rules[?(@.host=="alt.example.com")].http.paths[*]}{.backend.service.port.name}{"\n"}{end}' 2>/dev/null | tr '\n' ' ')
if [ "$ALTN" = "80 " ]; then
  ok "the / path on alt.example.com routes to port 80"
elif [ -n "${ALTNM// /}" ] && [ "${ALTNM// /}" != "0" ]; then
  case "$SVP" in
    *"${ALTNM// /}/80"*) ok "the / path on alt.example.com routes to port 80 (the named port ${ALTNM// /})";;
    *) bad "the / path on alt.example.com routes to port 80 (the named port '${ALTNM// /}' does not map to 80 on Service $DEP)";;
  esac
else
  bad "the / path on alt.example.com routes to port 80 (got number '$ALTN', name '$ALTNM')"
fi

# ---- the rewrite annotation ----
ANN=$(k -n "$NS" get ingress "$ING" \
  -o jsonpath="{.metadata.annotations['nginx.ingress.kubernetes.io/rewrite-target']}" 2>/dev/null | tr -d '\n')
if [ -z "$ANN" ]; then
  ANN=$(k -n "$NS" get ingress "$ING" -o json 2>/dev/null | tr -d ' \t\n' \
    | sed -n 's/.*"nginx.ingress.kubernetes.io\/rewrite-target":"\([^"]*\)".*/\1/p')
fi
eq "the annotation nginx.ingress.kubernetes.io/rewrite-target is set to /" "$ANN" "/"

note "One TLS entry per host. Each entry names the Secret that holds THAT host's"
note "certificate - a single entry listing both hosts would point both of them at"
note "one certificate, and the second host would present the wrong one."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}v13 PASSED${X}"; else echo -e "${R}v13 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
