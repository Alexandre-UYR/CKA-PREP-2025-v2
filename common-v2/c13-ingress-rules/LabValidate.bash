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

NS=ingress
ING=web

echo "== c13: Ingress with several rules =="

if ! exists "Ingress $ING exists in namespace $NS" -n "$NS" ingress "$ING"; then
  echo; echo -e "${R}c13 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the ingress class ----
eq "the Ingress uses the ingress class nginx" \
  "$(k -n "$NS" get ingress "$ING" -o jsonpath='{.spec.ingressClassName}' 2>/dev/null)" "nginx"

# ---- find the index of each rule by its host ----
# Prints the position of $2 inside the space separated list $1, or nothing.
idx_of(){
  local i=0 v
  for v in $1; do
    if [ "$v" = "$2" ]; then echo "$i"; return 0; fi
    i=$((i+1))
  done
  echo ""
}

HOSTS=$(k -n "$NS" get ingress "$ING" -o jsonpath='{.spec.rules[*].host}' 2>/dev/null)
SHOP_IDX=$(idx_of "$HOSTS" "shop.example.com")
API_IDX=$(idx_of "$HOSTS" "api.example.com")

nonempty "the Ingress has a rule for host shop.example.com" "$SHOP_IDX"
nonempty "the Ingress has a rule for host api.example.com" "$API_IDX"

# ---- rule one: shop.example.com ----
if [ -n "$SHOP_IDX" ]; then
  SHOP_PATHS=$(k -n "$NS" get ingress "$ING" -o jsonpath="{.spec.rules[$SHOP_IDX].http.paths[*].path}" 2>/dev/null)
  A_IDX=$(idx_of "$SHOP_PATHS" "/a")
  B_IDX=$(idx_of "$SHOP_PATHS" "/b")

  nonempty "the shop.example.com rule has a path /a" "$A_IDX"
  nonempty "the shop.example.com rule has a path /b" "$B_IDX"

  if [ -n "$A_IDX" ]; then
    eq "the path /a has pathType Prefix" \
      "$(k -n "$NS" get ingress "$ING" -o jsonpath="{.spec.rules[$SHOP_IDX].http.paths[$A_IDX].pathType}" 2>/dev/null)" "Prefix"
    eq "the path /a is routed to Service app-a" \
      "$(k -n "$NS" get ingress "$ING" -o jsonpath="{.spec.rules[$SHOP_IDX].http.paths[$A_IDX].backend.service.name}" 2>/dev/null)" "app-a"
    eq "the path /a is routed to port 80" \
      "$(k -n "$NS" get ingress "$ING" -o jsonpath="{.spec.rules[$SHOP_IDX].http.paths[$A_IDX].backend.service.port.number}" 2>/dev/null)" "80"
  else
    skip "the pathType / backend checks for /a (the rule has no path /a)"
  fi

  if [ -n "$B_IDX" ]; then
    eq "the path /b has pathType Prefix" \
      "$(k -n "$NS" get ingress "$ING" -o jsonpath="{.spec.rules[$SHOP_IDX].http.paths[$B_IDX].pathType}" 2>/dev/null)" "Prefix"
    eq "the path /b is routed to Service app-b" \
      "$(k -n "$NS" get ingress "$ING" -o jsonpath="{.spec.rules[$SHOP_IDX].http.paths[$B_IDX].backend.service.name}" 2>/dev/null)" "app-b"
    eq "the path /b is routed to port 80" \
      "$(k -n "$NS" get ingress "$ING" -o jsonpath="{.spec.rules[$SHOP_IDX].http.paths[$B_IDX].backend.service.port.number}" 2>/dev/null)" "80"
  else
    skip "the pathType / backend checks for /b (the rule has no path /b)"
  fi
else
  skip "all the shop.example.com path checks (there is no rule for that host)"
fi

# ---- rule two: api.example.com ----
if [ -n "$API_IDX" ]; then
  API_PATHS=$(k -n "$NS" get ingress "$ING" -o jsonpath="{.spec.rules[$API_IDX].http.paths[*].path}" 2>/dev/null)
  ROOT_IDX=$(idx_of "$API_PATHS" "/")

  nonempty "the api.example.com rule has a path /" "$ROOT_IDX"

  if [ -n "$ROOT_IDX" ]; then
    eq "the path / has pathType Prefix" \
      "$(k -n "$NS" get ingress "$ING" -o jsonpath="{.spec.rules[$API_IDX].http.paths[$ROOT_IDX].pathType}" 2>/dev/null)" "Prefix"
    eq "the path / is routed to Service app-a" \
      "$(k -n "$NS" get ingress "$ING" -o jsonpath="{.spec.rules[$API_IDX].http.paths[$ROOT_IDX].backend.service.name}" 2>/dev/null)" "app-a"
    eq "the path / is routed to port 80" \
      "$(k -n "$NS" get ingress "$ING" -o jsonpath="{.spec.rules[$API_IDX].http.paths[$ROOT_IDX].backend.service.port.number}" 2>/dev/null)" "80"
  else
    skip "the pathType / backend checks for / (the rule has no path /)"
  fi
else
  skip "all the api.example.com path checks (there is no rule for that host)"
fi

note "pathType is required in networking.k8s.io/v1 - a path without it is"
note "rejected by the API server."
note "A host with no matching path still falls through to the '/' prefix rule"
note "of the SAME host, which is what keeps shop.example.com and"
note "api.example.com apart."
note "No ingress controller is needed to create or to grade the object - the"
note "controller only matters when you want the traffic to actually arrive."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c13 PASSED${X}"; else echo -e "${R}c13 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
