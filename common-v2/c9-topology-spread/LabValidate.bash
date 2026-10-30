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
skip(){ echo -e "\033[33mSKIP${X}  $1"; }

NS=topology
DEP=spread
SEL=app=spread

echo "== c9: Spread pods across nodes =="

if ! exists "Deployment $DEP exists in namespace $NS" -n "$NS" deployment "$DEP"; then
  echo; echo -e "${R}c9 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the constraint ----
CONS=$(k -n "$NS" get deployment "$DEP" -o jsonpath='{.spec.template.spec.topologySpreadConstraints}' 2>/dev/null)
nonempty "the pod template carries a topologySpreadConstraint" "$CONS"

# Find the constraint that uses the hostname topology key, whatever position
# it is in the list.
IDX=""
i=0
while [ "$i" -lt 10 ]; do
  TK=$(k -n "$NS" get deployment "$DEP" -o jsonpath="{.spec.template.spec.topologySpreadConstraints[$i].topologyKey}" 2>/dev/null)
  if [ -z "$TK" ]; then break; fi
  if [ "$TK" = "kubernetes.io/hostname" ]; then IDX=$i; break; fi
  i=$((i+1))
done
if [ -z "$IDX" ]; then
  bad "a constraint uses topologyKey kubernetes.io/hostname (got '$CONS')"
else
  ok "a constraint uses topologyKey kubernetes.io/hostname"

  MS=$(k -n "$NS" get deployment "$DEP" -o jsonpath="{.spec.template.spec.topologySpreadConstraints[$IDX].maxSkew}" 2>/dev/null)
  eq "the constraint has maxSkew 1" "$MS" "1"

  WU=$(k -n "$NS" get deployment "$DEP" -o jsonpath="{.spec.template.spec.topologySpreadConstraints[$IDX].whenUnsatisfiable}" 2>/dev/null)
  eq "the constraint has whenUnsatisfiable ScheduleAnyway" "$WU" "ScheduleAnyway"

  ML=$(k -n "$NS" get deployment "$DEP" -o jsonpath="{.spec.template.spec.topologySpreadConstraints[$IDX].labelSelector.matchLabels.app}" 2>/dev/null)
  MEK=$(k -n "$NS" get deployment "$DEP" -o jsonpath="{.spec.template.spec.topologySpreadConstraints[$IDX].labelSelector.matchExpressions[0].key}" 2>/dev/null)
  MEV=$(k -n "$NS" get deployment "$DEP" -o jsonpath="{.spec.template.spec.topologySpreadConstraints[$IDX].labelSelector.matchExpressions[0].values[0]}" 2>/dev/null)
  if [ "$ML" = "spread" ]; then
    ok "the constraint's labelSelector matches $SEL"
  elif [ "$MEK" = "app" ] && [ "$MEV" = "spread" ]; then
    ok "the constraint's labelSelector matches $SEL"
  else
    bad "the constraint's labelSelector matches $SEL (matchLabels.app='$ML', matchExpressions[0].key='$MEK', matchExpressions[0].values[0]='$MEV')"
  fi
fi

# ---- the scale-up ----
REP=$(k -n "$NS" get deployment "$DEP" -o jsonpath='{.spec.replicas}' 2>/dev/null)
eq "the Deployment is scaled to 8 replicas" "$REP" "8"

RR=$(k -n "$NS" get deployment "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
if [ "$REP" = "8" ]; then
  # The new pods need a moment to start and become ready.
  i=0
  while [ "$i" -lt 60 ]; do
    RR=$(k -n "$NS" get deployment "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    if [ "$RR" = "8" ]; then break; fi
    i=$((i+1)); sleep 2
  done
fi
eq "all 8 replicas are ready" "$RR" "8"

# ---- the spread itself ----
NODES_TOTAL=$(k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | wc -l | tr -d ' ')
POD_NODES=$(k -n "$NS" get pods -l app=spread -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | sort -u | grep -c . || true)
if [ "${NODES_TOTAL:-0}" -lt 2 ]; then
  skip "this cluster has ${NODES_TOTAL:-0} node, so a spread cannot be observed"
elif [ "${POD_NODES:-0}" -ge 2 ]; then
  ok "the running pods are spread over at least 2 nodes (got $POD_NODES)"
else
  bad "the running pods are spread over at least 2 nodes (got ${POD_NODES:-0} distinct node names)"
fi

note "ScheduleAnyway tells the scheduler to prefer an even spread but never to"
note "refuse a placement: the pod is placed anyway, so a single-node cluster"
note "still works. DoNotSchedule would make the scheduler hold the pod back"
note "instead - with 8 replicas on 2 nodes the last ones would stay Pending."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c9 PASSED${X}"; else echo -e "${R}c9 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
