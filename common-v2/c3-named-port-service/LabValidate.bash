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

NS=namedport
DEP=web
SVC=web-svc

echo "== c3: Service on a named port =="

if ! exists "Deployment $DEP exists in namespace $NS" -n "$NS" deploy "$DEP"; then
  echo; echo -e "${R}c3 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the container must declare a NAMED port ----
PORTS=$(k -n "$NS" get deploy "$DEP" -o go-template='{{range .spec.template.spec.containers}}{{range .ports}}{{.name}}:{{.containerPort}}:{{.protocol}}{{"\n"}}{{end}}{{end}}' 2>/dev/null)
has "the container declares a containerPort named http on port 80 (TCP)" "$PORTS" "http:80:TCP"

# ---- the Service ----
if ! exists "Service $SVC exists in namespace $NS" -n "$NS" svc "$SVC"; then
  echo; echo -e "${R}c3 FAILED ($FAILS checks)${X}"; exit 1
fi

STYPE=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.type}' 2>/dev/null)
eq "the Service type is ClusterIP" "$STYPE" "ClusterIP"

# Find the Service's port entry that is named "http". The candidate may have
# added other ports, so do not assume it is the first one.
SPORTS=$(k -n "$NS" get svc "$SVC" -o go-template='{{range .spec.ports}}{{.name}}|{{.port}}|{{.targetPort}}|{{.protocol}}{{"\n"}}{{end}}' 2>/dev/null)
HTTP_LINE=$(printf '%s\n' "$SPORTS" | grep '^http|' | head -1)

if [ -z "$HTTP_LINE" ]; then
  bad "the Service has a port named http (got ports: '$(printf '%s' "$SPORTS" | tr '\n' ';')')"
else
  ok "the Service has a port named http"
  eq "the Service port is 80" "$(printf '%s' "$HTTP_LINE" | cut -d'|' -f2)" "80"
  eq "the Service targetPort is the NAME 'http', not the number 80" "$(printf '%s' "$HTTP_LINE" | cut -d'|' -f3)" "http"
  eq "the Service port protocol is TCP" "$(printf '%s' "$HTTP_LINE" | cut -d'|' -f4)" "TCP"
fi

# ---- wait for the rollout, otherwise the endpoint check is a race ----
i=0
while [ $i -lt 12 ]; do
  R=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  if [ "$R" = "1" ]; then break; fi
  i=$((i+1)); sleep 3
done
READY=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
eq "the Deployment $DEP has 1 ready replica" "$READY" "1"

# ---- does the Service really select the pods? ----
EPS=$(k -n "$NS" get endpoints "$SVC" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
nonempty "the Service $SVC has at least one endpoint address" "$EPS"

if [ -n "$EPS" ]; then
  EPORT=$(k -n "$NS" get endpoints "$SVC" -o jsonpath='{.subsets[*].ports[*].port}' 2>/dev/null)
  eq "the endpoint resolves to port 80 (the named container port)" "$EPORT" "80"
else
  skip "the endpoint resolves to port 80 (there are no endpoints to inspect)"
fi

note "A named targetPort is resolved against the pod's container ports by NAME."
note "If the container has no named port, the Service object still looks right,"
note "but it silently gets no endpoints - check with 'kubectl get endpoints'."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c3 PASSED${X}"; else echo -e "${R}c3 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
