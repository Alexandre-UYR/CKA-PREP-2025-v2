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

NS=cache
DEP=cache
SVC=cache
ENDPOINTS=/root/q3.json
HISTORY=/root/q3.txt

echo "== w1: What the cluster actually says =="

# ---- the Deployment and the Service are pre-state ----
exists "Deployment $DEP exists in namespace $NS" -n "$NS" deploy "$DEP"
exists "Service $SVC exists in namespace $NS" -n "$NS" svc "$SVC"

# ---- 2. the scale-up ----
REP=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.replicas}' 2>/dev/null)
eq "the Deployment is scaled to 5 replicas" "$REP" "5"

READY=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
eq "all 5 replicas are ready" "$READY" "5"

# ---- 4. the Service still works ----
NP=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
nonempty "the Service still has a nodePort" "$NP"
eq "the Service still targets port 11211" \
  "$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)" "11211"

EP=$(k -n "$NS" get endpoints "$SVC" -o jsonpath='{range .subsets[*].addresses[*]}{.ip}{"\n"}{end}' 2>/dev/null | grep -c '[0-9]' || true)
if [ "${EP:-0}" -ge 5 ] 2>/dev/null; then
  ok "the Service selects all 5 pod addresses ($EP endpoints)"
else
  bad "the Service selects all 5 pod addresses (got $EP)"
fi

# ---- 1. the endpoints file ----
if [ -f "$ENDPOINTS" ]; then
  ok "$ENDPOINTS exists"
  CONTENT=$(cat "$ENDPOINTS" 2>/dev/null)
  nonempty "$ENDPOINTS is not empty" "$CONTENT"
  # it has to be JSON
  if printf '%s' "$CONTENT" | grep -qE '^\s*[\[{]'; then
    ok "$ENDPOINTS looks like JSON"
  else
    bad "$ENDPOINTS looks like JSON (it does not start with [ or {)"
  fi
  # and it has to hold the addresses the Service actually resolves to
  MISSING=""
  for ip in $(k -n "$NS" get endpoints "$SVC" -o jsonpath='{range .subsets[*].addresses[*]}{.ip}{"\n"}{end}' 2>/dev/null); do
    has "$ENDPOINTS contains the endpoint $ip" "$CONTENT" "$ip" || MISSING="$MISSING $ip"
  done
  if [ -z "$MISSING" ]; then
    ok "$ENDPOINTS contains every endpoint address the Service resolves to"
  else
    bad "$ENDPOINTS contains every endpoint address the Service resolves to (missing:$MISSING)"
  fi
else
  bad "$ENDPOINTS exists (file not found)"
fi

# ---- 3. the history file ----
if [ -f "$HISTORY" ]; then
  ok "$HISTORY exists"
  HCONTENT=$(cat "$HISTORY" 2>/dev/null)
  nonempty "$HISTORY is not empty" "$HCONTENT"
  REVS=$(printf '%s\n' "$HCONTENT" | grep -cE '^[[:space:]]*[0-9]+[[:space:]]' || true)
  if [ "${REVS:-0}" -ge 2 ] 2>/dev/null; then
    ok "$HISTORY lists at least 2 revisions (got $REVS)"
  else
    bad "$HISTORY lists at least 2 revisions (got $REVS)"
  fi
  # the history has to mention the deployment's own revisions
  if printf '%s' "$HCONTENT" | grep -q "$DEP"; then
    ok "$HISTORY refers to the $DEP deployment"
  else
    bad "$HISTORY refers to the $DEP deployment"
  fi
else
  bad "$HISTORY exists (file not found)"
fi

note "The endpoints of a Service are the addresses of the pods its SELECTOR"
note "matches. If the selector matches nothing, the Service still exists and"
note "still has a nodePort - it just resolves to nothing."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}w1 PASSED${X}"; else echo -e "${R}w1 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
