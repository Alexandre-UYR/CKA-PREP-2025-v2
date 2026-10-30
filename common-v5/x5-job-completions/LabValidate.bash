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

echo "== x5: Ten of them, five at a time =="

if ! exists "Job $JOB exists in namespace $NS" -n "$NS" job "$JOB"; then
  echo; echo -e "${R}x5 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the three knobs --------------------------------------------------------

COMPL=$(k -n "$NS" get job "$JOB" -o jsonpath='{.spec.completions}' 2>/dev/null)
eq "the Job asks for 10 completions" "$COMPL" "10"

PARA=$(k -n "$NS" get job "$JOB" -o jsonpath='{.spec.parallelism}' 2>/dev/null)
eq "the Job runs 5 pods at a time" "$PARA" "5"

BO=$(k -n "$NS" get job "$JOB" -o jsonpath='{.spec.backoffLimit}' 2>/dev/null)
if [ -n "$BO" ] && [ "$BO" -ge 1 ] 2>/dev/null && [ "$BO" -le 6 ] 2>/dev/null; then
  ok "the Job has a backoffLimit set, between 1 and 6 (it is $BO)"
else
  bad "the Job has a backoffLimit set, between 1 and 6 (got '$BO')"
fi

# ---- the same container -----------------------------------------------------

IMG=$(k -n "$NS" get job "$JOB" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
case "$IMG" in
  busybox:1.36) ok "the Job still runs the same container ($IMG)";;
  busybox:*)    ok "the Job still runs the same container (it runs $IMG)";;
  *)            bad "the Job still runs the same container (it runs '${IMG:-<nothing>}')";;
esac

# ---- ten successful completions ---------------------------------------------
# Give the Job controller a moment: ten completions at five at a time take a
# few seconds, and the candidate may have moved on the moment the last pod
# finished.

echo "Waiting for the Job to reach ten successful completions..."
SUCC=""
i=0
while [ "$i" -lt 60 ]; do
  SUCC=$(k -n "$NS" get job "$JOB" -o jsonpath='{.status.succeeded}' 2>/dev/null)
  [ "$SUCC" = "10" ] && break
  sleep 2
  i=$((i+2))
done
eq "the Job has 10 successful completions" "$SUCC" "10"

COMPLETECOND=$(k -n "$NS" get job "$JOB" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null)
eq "the Job's Complete condition is True" "$COMPLETECOND" "True"

FAILEDCOND=$(k -n "$NS" get job "$JOB" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null)
if [ "$FAILEDCOND" = "True" ]; then
  bad "the Job does not carry the Failed condition (it still has one)"
else
  ok "the Job does not carry the Failed condition"
fi

# ---- the pods ---------------------------------------------------------------

JUID=$(k -n "$NS" get job "$JOB" -o jsonpath='{.metadata.uid}' 2>/dev/null)
PODS=$(k -n "$NS" get pods -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{range .metadata.ownerReferences[*]}{.uid}{","}{end}{"|"}{.status.phase}{"\n"}{end}' 2>/dev/null)

TOTAL=0
SUCCPODS=0
FAILPODS=0
while IFS= read -r row; do
  [ -n "$row" ] || continue
  PUID=$(printf '%s' "$row" | cut -d'|' -f2)
  PHASE=$(printf '%s' "$row" | cut -d'|' -f3)
  [ "$PUID" = "$JUID," ] || continue
  TOTAL=$((TOTAL+1))
  case "$PHASE" in
    Succeeded) SUCCPODS=$((SUCCPODS+1));;
    Failed)    FAILPODS=$((FAILPODS+1));;
  esac
done <<EOF
$PODS
EOF

if [ "$TOTAL" -ge 10 ] 2>/dev/null; then
  ok "the Job has ten pods of its own (it has $TOTAL)"
else
  bad "the Job has ten pods of its own (it has $TOTAL)"
fi
eq "all ten of the Job's pods reached the Succeeded phase" "$SUCCPODS" "10"
if [ "$FAILPODS" -gt 0 ] 2>/dev/null; then
  note "There are $FAILPODS failed pod(s) in the namespace - the Job retried"
  note "them and carried on, which is what backoffLimit is for."
fi

note "completions is how many pods must SUCCEED, parallelism is how many run at"
note "once, and backoffLimit is how many failures are tolerated before the Job"
note "gives up. A Job's pod template is immutable, so the Job has to be deleted"
note "and re-created - with the same name and the same container."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}x5 PASSED${X}"; else echo -e "${R}x5 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
