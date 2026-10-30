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

NS=reports
DEP=website
A=/root/q6a.txt
B=/root/q6b.txt

echo "== w5: The same pods, three ways =="

# ---- the pre-state ---------------------------------------------------------

exists "Deployment $DEP exists in namespace $NS" -n "$NS" deploy "$DEP"

# ---- the live pods ---------------------------------------------------------

PODNAMES=$(k -n "$NS" get pods -l "app=$DEP" \
             -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
NPODS=$(printf '%s\n' "$PODNAMES" | grep -c '[^[:space:]]' || true)
eq "the Deployment has 5 pods" "$NPODS" "5"

# The pods with their IP, so the order in the first file can be checked
# against the addresses the cluster has right now.
IPNAME=""
for p in $PODNAMES; do
  [ -n "$p" ] || continue
  ip=$(k -n "$NS" get pod "$p" -o jsonpath='{.status.podIP}' 2>/dev/null || true)
  if [ -z "$ip" ]; then
    continue
  fi
  IPNAME="${IPNAME}${ip} ${p}
"
done

# ---- the two files ---------------------------------------------------------

ACONTENT=""
BCONTENT=""
if [ -f "$A" ]; then
  ok "$A exists"
  ACONTENT=$(cat "$A" 2>/dev/null)
  nonempty "$A is not empty" "$ACONTENT"
else
  bad "$A exists (file not found)"
fi

if [ -f "$B" ]; then
  ok "$B exists"
  BCONTENT=$(cat "$B" 2>/dev/null)
  nonempty "$B is not empty" "$BCONTENT"
else
  bad "$B exists (file not found)"
fi

# ---- one row per pod, and every pod in both files --------------------------

if [ -n "$ACONTENT" ]; then
  ROWSA=$(printf '%s\n' "$ACONTENT" | grep -c "${DEP}-" || true)
  eq "$A has one row per pod (5 rows)" "$ROWSA" "5"
fi

if [ -n "$BCONTENT" ]; then
  ROWSB=$(printf '%s\n' "$BCONTENT" | grep -c "${DEP}-" || true)
  eq "$B has one row per pod (5 rows)" "$ROWSB" "5"
fi

for p in $PODNAMES; do
  [ -n "$p" ] || continue
  if [ -n "$ACONTENT" ]; then
    has "$A contains the pod name $p" "$ACONTENT" "$p"
  fi
  if [ -n "$BCONTENT" ]; then
    has "$B contains the pod name $p" "$BCONTENT" "$p"
  fi
done

# ---- the first file carries the labels -------------------------------------

if [ -n "$ACONTENT" ]; then
  if printf '%s' "$ACONTENT" | grep -q 'app=website'; then
    ok "$A carries the label app=website"
  elif printf '%s' "$ACONTENT" | grep -q 'app' && printf '%s' "$ACONTENT" | grep -q 'website'; then
    ok "$A carries the label app=website (in map form)"
  else
    bad "$A carries the label app=website (got '$ACONTENT')"
  fi
fi

# ---- the second file carries the phase, and NOT the labels -----------------

if [ -n "$BCONTENT" ]; then
  RUNNING=$(printf '%s\n' "$BCONTENT" | grep -c 'Running' || true)
  if [ "${RUNNING:-0}" -ge 5 ]; then
    ok "$B carries the phase Running for every pod ($RUNNING rows)"
  else
    bad "$B carries the phase Running for every pod (got ${RUNNING:-0}, want 5)"
  fi

  if printf '%s' "$BCONTENT" | grep -q 'app='; then
    bad "$B does not carry the label text (it contains 'app=')"
  else
    ok "$B does not carry the label text"
  fi
fi

# ---- the first file is sorted by pod IP ------------------------------------

if [ -z "$IPNAME" ]; then
  skip "the pods in $A are in ascending order of pod IP (no pod has an IP yet)"
else
  # The pod names in ascending order of their IP. The IP is turned into a
  # fixed-width key so that a plain lexicographic sort gives the same order
  # as a numeric one.
  EXPECTED=$(printf '%s\n' "$IPNAME" | awk '
    NF < 2 { next }
    {
      split($1, o, ".");
      key = sprintf("%03d%03d%03d%03d", o[1], o[2], o[3], o[4]);
      printf "%s\t%s\n", key, $2;
    }' | sort | cut -f2 | tr '\n' ' ')
  EXPECTED=${EXPECTED% }

  ACTUAL=""
  if [ -n "$ACONTENT" ]; then
    ACTUAL=$(printf '%s\n' "$ACONTENT" | grep -oE "${DEP}-[[:alnum:]-]+" | tr '\n' ' ')
    ACTUAL=${ACTUAL% }
  fi

  if [ -n "$ACTUAL" ]; then
    eq "the pods in $A are in ascending order of pod IP" "$ACTUAL" "$EXPECTED"
  else
    bad "the pods in $A are in ascending order of pod IP (no pod names found in the file)"
  fi
fi

note "The labels belong in $A and not in $B. That difference is what the two"
note "files are for, and the grader checks both directions."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}w5 PASSED${X}"; else echo -e "${R}w5 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
