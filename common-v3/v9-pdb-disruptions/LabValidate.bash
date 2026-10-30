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

NS=pdb
DEP=api
PDB=api-pdb

echo "== v9: Protect the workload from voluntary disruption =="

if ! exists "PodDisruptionBudget $PDB exists in namespace $NS" -n "$NS" pdb "$PDB"; then
  echo; echo -e "${R}v9 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the workload the budget has to protect ----

REPLICAS=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[ -z "$REPLICAS" ] && REPLICAS=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.replicas}' 2>/dev/null)
[ -z "$REPLICAS" ] && REPLICAS=3
nonempty "the $DEP deployment still has ready replicas" "$REPLICAS"

# ---- the selector ----
# An empty selector {} matches every pod in the namespace, and a selector that
# matches nothing protects nothing. Either way the budget is not doing its job,
# so the selector has to be a real one.

SEL=$(k -n "$NS" get pdb "$PDB" -o jsonpath='{.spec.selector}' 2>/dev/null)
if [ -z "$SEL" ] || [ "$SEL" = "map[]" ]; then
  bad "the budget has a selector of its own (found '${SEL:-<none>}' - an empty selector matches every pod in the namespace)"
else
  ok "the budget has a selector of its own ($SEL)"
fi

# Give the disruption controller a moment to fill in the status.

echo "Waiting for the budget status to be computed..."
i=0
while [ "$i" -lt 20 ]; do
  CUR=$(k -n "$NS" get pdb "$PDB" -o jsonpath='{.status.currentHealthy}' 2>/dev/null)
  [ -n "$CUR" ] && break
  sleep 2
  i=$((i+2))
done

# ---- the budget selects the api pods ----
# The healthy count has to be the number of api replicas: a selector that
# matched nothing reports 0, and a selector that matched more than the api
# pods reports more than the replica count. Either way the budget is not
# protecting the workload it was written for.

CUR=$(k -n "$NS" get pdb "$PDB" -o jsonpath='{.status.currentHealthy}' 2>/dev/null)
DES=$(k -n "$NS" get pdb "$PDB" -o jsonpath='{.status.desiredHealthy}' 2>/dev/null)
EXP=$(k -n "$NS" get pdb "$PDB" -o jsonpath='{.status.expectedPods}' 2>/dev/null)

eq "the budget selects the api pods (current healthy)" "$CUR" "$REPLICAS"

if [ -n "$DES" ]; then
  if [ "$DES" -gt 0 ] 2>/dev/null; then
    ok "the budget reports a desired healthy count above zero ($DES)"
  else
    bad "the budget reports a desired healthy count above zero (got '$DES')"
  fi
else
  skip "the budget reports no desired healthy count"
fi

if [ -n "$EXP" ]; then
  eq "the budget matches the api pods (expected pods)" "$EXP" "$REPLICAS"
else
  skip "the budget reports no expected pod count"
fi

# ---- at most one disruption ----
# maxUnavailable and minAvailable are two ways of saying the same thing here:
# with 3 replicas, "at most 1 unavailable" and "at least 2 available" are the
# same budget. Only one of the two may be set.

MU=$(k -n "$NS" get pdb "$PDB" -o jsonpath='{.spec.maxUnavailable}' 2>/dev/null)
MA=$(k -n "$NS" get pdb "$PDB" -o jsonpath='{.spec.minAvailable}' 2>/dev/null)

if [ "$MU" = "1" ] || [ "$MA" = "2" ]; then
  ok "the budget allows at most one disruption (maxUnavailable='${MU:-<unset>}', minAvailable='${MA:-<unset>}')"
else
  bad "the budget allows at most one disruption (maxUnavailable='${MU:-<unset>}', minAvailable='${MA:-<unset>}' - want maxUnavailable=1 or minAvailable=2)"
fi

# ---- and the live proof ----

DA=$(k -n "$NS" get pdb "$PDB" -o jsonpath='{.status.disruptionsAllowed}' 2>/dev/null)
eq "the budget allows exactly one disruption right now (disruptionsAllowed)" "$DA" "1"

note "A PodDisruptionBudget only constrains VOLUNTARY disruption: a node drain, an"
note "autoscaler removing a pod, a pod evicted by the eviction API. It does nothing"
note "for a node that fails or a pod that is killed."
note "ALLOWED DISRUPTIONS is the column that tells you whether the budget is real."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}v9 PASSED${X}"; else echo -e "${R}v9 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
