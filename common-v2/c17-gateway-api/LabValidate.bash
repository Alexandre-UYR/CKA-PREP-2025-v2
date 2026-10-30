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

echo "== c17: Gateway API basics =="

# ---- step 1: the CRDs ----
exists "the CRD gateways.gateway.networking.k8s.io is installed" crd gateways.gateway.networking.k8s.io
exists "the CRD httproutes.gateway.networking.k8s.io is installed" crd httproutes.gateway.networking.k8s.io

# ---- step 2: the Gateway ----
# The candidate may legitimately put the Gateway in any namespace, so look for
# it across the whole cluster and remember where it was found.
GW_NS=$(k get gateways.gateway.networking.k8s.io -A -o jsonpath='{range .items[?(@.metadata.name=="edge")]}{.metadata.namespace}{"\n"}{end}' 2>/dev/null | head -1 | tr -d '[:space:]')
if [ -n "$GW_NS" ]; then
  ok "a Gateway named edge exists (namespace $GW_NS)"
else
  bad "a Gateway named edge exists somewhere in the cluster (none found)"
fi

GW_CLASS=""
GW_PROTO=""
GW_PORT=""
if [ -n "$GW_NS" ]; then
  GW_CLASS=$(k -n "$GW_NS" get gateways.gateway.networking.k8s.io edge -o jsonpath='{.spec.gatewayClassName}' 2>/dev/null)
  GW_PROTO=$(k -n "$GW_NS" get gateways.gateway.networking.k8s.io edge -o jsonpath='{.spec.listeners[*].protocol}' 2>/dev/null)
  GW_PORT=$(k -n "$GW_NS" get gateways.gateway.networking.k8s.io edge -o jsonpath='{.spec.listeners[*].port}' 2>/dev/null)
fi

eq "the Gateway uses gatewayClassName nginx" "$GW_CLASS" "nginx"
has "the Gateway has a listener with protocol HTTP" " $GW_PROTO " " HTTP "
has "the Gateway has a listener on port 80" " $GW_PORT " " 80 "

# ---- step 3: the HTTPRoute ----
HR_NS=$(k get httproutes.gateway.networking.k8s.io -A -o jsonpath='{range .items[?(@.metadata.name=="edge-route")]}{.metadata.namespace}{"\n"}{end}' 2>/dev/null | head -1 | tr -d '[:space:]')
if [ -n "$HR_NS" ]; then
  ok "an HTTPRoute named edge-route exists (namespace $HR_NS)"
else
  bad "an HTTPRoute named edge-route exists somewhere in the cluster (none found)"
fi

HR_HOSTS=""
HR_PARENTS=""
HR_BACKENDS=""
HR_BPORTS=""
if [ -n "$HR_NS" ]; then
  HR_HOSTS=$(k -n "$HR_NS" get httproutes.gateway.networking.k8s.io edge-route -o jsonpath='{.spec.hostnames[*]}' 2>/dev/null)
  HR_PARENTS=$(k -n "$HR_NS" get httproutes.gateway.networking.k8s.io edge-route -o jsonpath='{.spec.parentRefs[*].name}' 2>/dev/null)
  HR_BACKENDS=$(k -n "$HR_NS" get httproutes.gateway.networking.k8s.io edge-route -o jsonpath='{.spec.rules[*].backendRefs[*].name}' 2>/dev/null)
  HR_BPORTS=$(k -n "$HR_NS" get httproutes.gateway.networking.k8s.io edge-route -o jsonpath='{.spec.rules[*].backendRefs[*].port}' 2>/dev/null)
fi

has "the HTTPRoute serves the host app.example.com" " $HR_HOSTS " " app.example.com "
has "the HTTPRoute attaches to the Gateway edge" " $HR_PARENTS " " edge "
has "the HTTPRoute routes to the Service web" " $HR_BACKENDS " " web "
has "the HTTPRoute backendRef targets port 80" " $HR_BPORTS " " 80 "

# ---- the pre-state the route points at is still intact ----
SVC=$(k get svc -A -o jsonpath='{range .items[?(@.metadata.name=="web")]}{range .spec.ports[*]}({.port}){end}{"\n"}{end}' 2>/dev/null)
has "a Service named web still exposes port 80" "$SVC" "(80)"

note "The Gateway API CRDs are cluster-scoped. Deleting a CRD destroys every"
note "object of that kind in the cluster, so the reset never removes them."
note "The Gateway and the HTTPRoute are namespaced, and a route may legitimately"
note "live in a different namespace from the Gateway it attaches to - both were"
note "searched across all namespaces here."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c17 PASSED${X}"; else echo -e "${R}c17 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
