#!/bin/bash
# Grader for Question 7 (PriorityClass).
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

exists "PriorityClass high-priority exists" priorityclass high-priority

# The value must be one less than the highest USER-DEFINED priority class.
# The system classes (system-cluster-critical = 2000000000, system-node-critical
# = 2000000001) are excluded -- they are not user-defined.
MAXV="$(k get priorityclass -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.value}{"\n"}{end}' 2>/dev/null \
  | awk '$1 !~ /^system-/ { v = $2 + 0; if (!seen || v > m) { m = v; seen = 1 } } END { if (seen) print m; else print "" }')"
if [ -n "$MAXV" ]; then
  WANT=$(( MAXV - 1 ))
  eq "PriorityClass high-priority value is one below the highest user-defined value ($MAXV - 1)" \
     "$(k get priorityclass high-priority -o jsonpath='{.value}' 2>/dev/null)" "$WANT"
else
  bad "PriorityClass high-priority value is one below the highest user-defined value (could not list user-defined PriorityClasses)"
fi

# The task says to PATCH the deployment, so the deployment must not have been
# recreated: its UID has to be the one captured at setup time.
ORIG_UID="$(cat /tmp/cka-lab/q7.deploy.uid 2>/dev/null)"
CUR_UID="$(k get deploy busybox-logger -n priority -o jsonpath='{.metadata.uid}' 2>/dev/null)"
if [ -z "$ORIG_UID" ]; then
  bad "deployment busybox-logger was patched, not recreated (no uid recorded at setup time)"
else
  eq "deployment busybox-logger was patched, not recreated (uid unchanged)" "$CUR_UID" "$ORIG_UID"
fi

eq "busybox-logger pod template uses priorityClassName high-priority" \
   "$(k get deploy busybox-logger -n priority -o jsonpath='{.spec.template.spec.priorityClassName}' 2>/dev/null)" \
   "high-priority"

if [ "$FAILS" -eq 0 ]; then echo -e "${G}Q7 PASSED${X}"; else echo -e "${R}Q7 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
