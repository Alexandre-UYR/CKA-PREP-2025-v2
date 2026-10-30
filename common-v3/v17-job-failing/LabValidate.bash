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

NS=jobs
JOB=import

echo "== v17: The Job that will never finish =="

if ! exists "Job $JOB exists in namespace $NS" -n "$NS" job "$JOB"; then
  echo; echo -e "${R}v17 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the knobs the task says to keep --------------------------------------

COMPL=$(k -n "$NS" get job "$JOB" -o jsonpath='{.spec.completions}' 2>/dev/null)
eq "the Job still asks for 3 completions" "$COMPL" "3"

BO=$(k -n "$NS" get job "$JOB" -o jsonpath='{.spec.backoffLimit}' 2>/dev/null)
if [ -n "$BO" ] && [ "$BO" -le 2 ] 2>/dev/null; then
  ok "the backoffLimit is 2 or lower (it is $BO)"
else
  bad "the backoffLimit is 2 or lower (got '$BO')"
fi

# ---- the container no longer fails on its own ------------------------------

TPL=$(k -n "$NS" get job "$JOB" -o jsonpath='{.spec.template}' 2>/dev/null)
case "$TPL" in
  *"exit 1"*) bad "the Job's container no longer exits 1 straight away (the template still says 'exit 1')";;
  *) ok "the Job's container no longer exits 1 straight away";;
esac

# ---- the Job has finished ---------------------------------------------------

SUCC=$(k -n "$NS" get job "$JOB" -o jsonpath='{.status.succeeded}' 2>/dev/null)
eq "the Job has 3 successful completions" "$SUCC" "3"

COMPLETECOND=$(k -n "$NS" get job "$JOB" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null)
eq "the Job's Complete condition is True" "$COMPLETECOND" "True"

FAILEDCOND=$(k -n "$NS" get job "$JOB" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null)
if [ "$FAILEDCOND" = "True" ]; then
  bad "the Job no longer carries the Failed condition (it still has one)"
else
  ok "the Job no longer carries the Failed condition"
fi

# ---- the Job's own pods ------------------------------------------------------

# The pods of the CURRENT Job are the ones whose ownerReference carries this
# Job's UID. (The `job-name` label would do too, but the ownerReference is
# the thing that actually says who owns the pod.)
JUID=$(k -n "$NS" get job "$JOB" -o jsonpath='{.metadata.uid}' 2>/dev/null)
PODS=$(k -n "$NS" get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)

TOTAL=0
SUCCPODS=0
FAILPODS=0
LEFTOVER=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  PH=$(k -n "$NS" get pod "$p" -o jsonpath='{.status.phase}' 2>/dev/null)
  PUID=$(k -n "$NS" get pod "$p" -o jsonpath='{.metadata.ownerReferences[0].uid}' 2>/dev/null)
  if [ "$PUID" != "$JUID" ]; then
    [ "$PH" = "Failed" ] && LEFTOVER=$((LEFTOVER+1))
    continue
  fi
  TOTAL=$((TOTAL+1))
  case "$PH" in
    Succeeded) SUCCPODS=$((SUCCPODS+1));;
    Failed)    FAILPODS=$((FAILPODS+1));;
  esac
done <<EOF
$PODS
EOF

eq "the Job has three pods of its own" "$TOTAL" "3"
eq "all three of the Job's pods reached the Succeeded phase" "$SUCCPODS" "3"
eq "none of the Job's pods is Failed" "$FAILPODS" "0"

# Leftovers from the Job that failed before the fix are not the Job's fault,
# but they are worth pointing out.
if [ "$LEFTOVER" -gt 0 ] 2>/dev/null; then
  note "There are still $LEFTOVER failed pod(s) in the namespace from the old Job."
  note "They belong to the Job that was replaced, not to the Job that completed."
fi

note "A Job's pods are never restarted: a failed pod stays failed, and the Job"
note "makes a NEW pod instead. backoffLimit is how many failures it tolerates."
note "The pod template is immutable, so the fix is a new Job with the old name."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}v17 PASSED${X}"; else echo -e "${R}v17 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
