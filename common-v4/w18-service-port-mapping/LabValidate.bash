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

NS=web
DEP=site
SVC=site-svc

echo "== w18: The Service's port is not the container's port =="

# ---- the pre-state ----
exists "Deployment $DEP exists in namespace $NS" -n "$NS" deploy "$DEP"

# The container port the Service's targetPort has to refer to.
CPORTNAME=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.template.spec.containers[0].ports[0].name}' 2>/dev/null)
eq "the container declares a port named 'http'" "$CPORTNAME" "http"
CPORTNUM=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.template.spec.containers[0].ports[0].containerPort}' 2>/dev/null)
eq "the container port is 80" "$CPORTNUM" "80"

# ---- the Service ----
if k -n "$NS" get svc "$SVC" >/dev/null 2>&1; then
  ok "Service $SVC exists in namespace $NS"
else
  bad "Service $SVC exists in namespace $NS (not found)"
fi

PNAME=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.ports[0].name}' 2>/dev/null)
eq "the Service's port is named 'http'" "$PNAME" "http"

PPORT=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
eq "the Service's port is 8080" "$PPORT" "8080"

# Compared as text on purpose: 'http' is the answer, the number 80 is not.
TPORT=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)
eq "the Service's targetPort is the name 'http'" "$TPORT" "http"

# ---- the selector has to match the pods' labels ----
SELCOUNT=$(k -n "$NS" get svc "$SVC" -o go-template='{{len .spec.selector}}' 2>/dev/null)
if [ "${SELCOUNT:-0}" -ge 1 ] 2>/dev/null; then
  ok "the Service has a selector"
else
  bad "the Service has a selector (got '${SELCOUNT:-?}')"
fi

SEL=$(k -n "$NS" get svc "$SVC" -o go-template='{{range $k, $v := .spec.selector}}{{$k}}={{$v}} {{end}}' 2>/dev/null)
for entry in $SEL; do
  KEY=${entry%%=*}
  VAL=${entry#*=}
  PODLABEL=$(k -n "$NS" get deploy "$DEP" -o jsonpath="{.spec.template.metadata.labels.$KEY}" 2>/dev/null)
  eq "the Service selector '$KEY=$VAL' matches the pods' label" "$PODLABEL" "$VAL"
done

# ---- and the Service really resolves to the pods ----
EP=0
for i in $(seq 1 15); do
  EP=$(k -n "$NS" get endpoints "$SVC" -o jsonpath='{range .subsets[*].addresses[*]}{.ip}{"\n"}{end}' 2>/dev/null | grep -c '[0-9]' || true)
  if [ "${EP:-0}" -ge 5 ] 2>/dev/null; then break; fi
  sleep 2
done
if [ "${EP:-0}" -ge 5 ] 2>/dev/null; then
  ok "the Service selects the pods ($EP endpoint addresses)"
else
  bad "the Service selects the pods (got $EP endpoint addresses, want at least 5)"
fi

note "The Service's 'port' is what clients connect to and 'targetPort' is"
note "where the traffic is sent on the pod. A named targetPort is resolved"
note "against the CONTAINER's port names, so the container has to declare one."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}w18 PASSED${X}"; else echo -e "${R}w18 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
