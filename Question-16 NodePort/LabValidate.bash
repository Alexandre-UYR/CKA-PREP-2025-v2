#!/bin/bash
# Grader for Question 16 (NodePort).
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

# 1. The deployment must expose a container port named http on port 80 / TCP.
#
# The container is NOT called "nginx": `kubectl create deployment` names the
# container after the deployment, so it is "nodeport-deployment". Any container
# is accepted, so all containers are scanned.
exists "deployment nodeport-deployment exists in namespace relative" deployment nodeport-deployment -n relative

PORTS="$(k get deployment nodeport-deployment -n relative \
  -o jsonpath='{range .spec.template.spec.containers[*]}{range .ports[*]}{.name}{" "}{.containerPort}{" "}{.protocol}{"\n"}{end}{end}' 2>/dev/null)"
HTTPLINE="$(printf '%s\n' "$PORTS" | grep '^http ' | head -1)"
if [ -n "$HTTPLINE" ]; then
  ok "a container port named http exists on the deployment"
else
  bad "a container port named http exists on the deployment (got ports: '$(printf '%s' "$PORTS" | tr '\n' ';')')"
fi
eq "the named http container port is containerPort 80" "$(printf '%s' "$HTTPLINE" | awk '{print $2}')" "80"
eq "the named http container port uses protocol TCP" "$(printf '%s' "$HTTPLINE" | awk '{print $3}')" "TCP"

# 2. A Service named nodeport-service of type NodePort.
exists "Service nodeport-service exists in namespace relative" service nodeport-service -n relative

eq "Service nodeport-service type is NodePort" \
   "$(k get service nodeport-service -n relative -o jsonpath='{.spec.type}' 2>/dev/null)" "NodePort"

# Read every port entry as: <port> <targetPort> <protocol> <nodePort>
SVCPORTS="$(k get service nodeport-service -n relative \
  -o jsonpath='{range .spec.ports[*]}{.port}{" "}{.targetPort}{" "}{.protocol}{" "}{.nodePort}{"\n"}{end}' 2>/dev/null)"
NP_LINE="$(printf '%s\n' "$SVCPORTS" | grep ' 30080$' | head -1)"
[ -n "$NP_LINE" ] || NP_LINE="$(printf '%s\n' "$SVCPORTS" | head -1)"

SP_PORT="$(printf '%s' "$NP_LINE" | awk '{print $1}')"
SP_TARGET="$(printf '%s' "$NP_LINE" | awk '{print $2}')"
SP_PROTO="$(printf '%s' "$NP_LINE" | awk '{print $3}')"
SP_NODEPORT="$(printf '%s' "$NP_LINE" | awk '{print $4}')"

eq "Service nodeport-service exposes nodePort 30080" "$SP_NODEPORT" "30080"
eq "Service nodeport-service port is 80" "$SP_PORT" "80"
eq "Service nodeport-service protocol is TCP" "$SP_PROTO" "TCP"
if [ "$SP_TARGET" = "80" ] || [ "$SP_TARGET" = "http" ]; then
  ok "Service nodeport-service targetPort resolves to container port 80 (got '$SP_TARGET')"
else
  bad "Service nodeport-service targetPort resolves to container port 80 (got '$SP_TARGET', want '80')"
fi

# The Service selector must actually select the deployment's pods.
ENDPOINTS=""
EPCOUNT=0
for i in $(seq 1 12); do
  ENDPOINTS="$(k get endpoints nodeport-service -n relative \
    -o jsonpath='{range .subsets[*].addresses[*]}{.ip}{" "}{end}' 2>/dev/null)"
  if [ -z "$ENDPOINTS" ]; then
    ENDPOINTS="$(k get endpointslice -n relative -l kubernetes.io/service-name=nodeport-service \
      -o jsonpath='{range .items[*].endpoints[*].addresses[*]}{.}{" "}{end}' 2>/dev/null)"
  fi
  EPCOUNT="$(printf '%s' "$ENDPOINTS" | wc -w | tr -d ' ')"
  [ "${EPCOUNT:-0}" -ge 2 ] && break
  sleep 5
done
if [ "${EPCOUNT:-0}" -ge 2 ]; then
  ok "Service nodeport-service selects the deployment pods ($EPCOUNT endpoint addresses)"
else
  bad "Service nodeport-service selects the deployment pods (got $EPCOUNT endpoint addresses, want at least 2)"
fi

# 3. "Configure the new Service to also expose the individual pods using
#    NodePort" -- the wording is ambiguous. Either of these satisfies it.
PNRA="$(k get service nodeport-service -n relative -o jsonpath='{.spec.publishNotReadyAddresses}' 2>/dev/null)"
ETP="$(k get service nodeport-service -n relative -o jsonpath='{.spec.externalTrafficPolicy}' 2>/dev/null)"
if [ "$PNRA" = "true" ] || [ "$ETP" = "Local" ]; then
  ok "Service exposes the individual pods via NodePort (publishNotReadyAddresses=$PNRA, externalTrafficPolicy=$ETP)"
else
  bad "Service must also expose the individual pods via NodePort: set spec.publishNotReadyAddresses=true OR spec.externalTrafficPolicy=Local (got publishNotReadyAddresses='$PNRA', externalTrafficPolicy='$ETP')"
fi

if [ "$FAILS" -eq 0 ]; then echo -e "${G}Q16 PASSED${X}"; else echo -e "${R}Q16 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
