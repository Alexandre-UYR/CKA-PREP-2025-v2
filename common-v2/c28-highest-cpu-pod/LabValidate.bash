#!/bin/bash
# Grader for c28 (find the hottest Pod).
#
# The interesting check - "is it really the pod with the most CPU?" - is made
# against the LIVE reading, because the answer is the name of a running pod
# and the pod names carry a random suffix. If `kubectl top pods` does not
# work in this cluster there is nothing to compare against, so that one
# check is SKIPPED with a reason; the file's existence, its format and the
# command file are still graded.
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

NS=metrics
ANSWER_FILE=/root/hot-pod.txt
COMMAND_FILE=/root/hot-pod-command.txt

echo "== c28: Find the hottest Pod =="

# ---- the answer file ----
PODNAME=""
if [ -f "$ANSWER_FILE" ]; then
  ok "the answer file $ANSWER_FILE exists"

  LINES=$(awk 'END{print NR+0}' "$ANSWER_FILE" 2>/dev/null || echo 0)
  eq "the answer file contains exactly one line" "$LINES" "1"

  LINE1=$(sed -n '1p' "$ANSWER_FILE" 2>/dev/null | tr -d '\r')
  if printf '%s' "$LINE1" | grep -Eq '^metrics/[a-z0-9]([-a-z0-9]*[a-z0-9])?$'; then
    ok "the answer line is of the form namespace/podname ('$LINE1')"
    PODNAME=$(printf '%s' "$LINE1" | sed 's|^metrics/||')
  else
    bad "the answer line is of the form namespace/podname (got '$LINE1', want 'metrics/<podname>')"
  fi
else
  bad "the answer file $ANSWER_FILE exists"
  skip "the contents of the answer file (there is no $ANSWER_FILE to read)"
fi

# ---- is it the right pod? ----
if [ -n "$PODNAME" ]; then
  TOP_OUT=$(k top pods -n "$NS" --no-headers 2>&1)
  TOP_RC=$?
  if [ "$TOP_RC" -ne 0 ] || [ -z "$TOP_OUT" ]; then
    REASON=$(printf '%s' "$TOP_OUT" | head -1)
    skip "comparing the answer against the live CPU reading (kubectl top pods does not work in this cluster: ${REASON:-no output})"
    note "Without a metrics server there is no reading to compare against, so"
    note "this is not counted as a failure."
  else
    PARSED=$(printf '%s\n' "$TOP_OUT" | awk 'NF>=2 && $1 != "NAME" { c=$2; if (c ~ /m$/) v=c+0; else v=c*1000; print v, $1 }')
    TOPPODS=$(printf '%s\n' "$PARSED" | awk 'NF>=2 { v=$1+0; if (v > m) { m=v; names=$2 } else if (v == m) { names = names " " $2 } } END { print names }')
    if [ -z "$TOPPODS" ]; then
      skip "comparing the answer against the live CPU reading (kubectl top pods returned no rows)"
    elif printf '%s' " $TOPPODS " | grep -q " $PODNAME "; then
      ok "the answer pod $PODNAME is the one using the most CPU (highest: $TOPPODS)"
    else
      bad "the answer pod $PODNAME is the one using the most CPU (pod(s) with the most CPU: ${TOPPODS:-none})"
    fi
  fi
fi

# ---- the command file ----
if [ -f "$COMMAND_FILE" ]; then
  ok "the command file $COMMAND_FILE exists"
  CMD=$(tr -d '\r' < "$COMMAND_FILE" 2>/dev/null || true)
  nonempty "the command file is not empty" "$CMD"
  if printf '%s' "$CMD" | grep -Eq -- '--selector|(^|[[:space:]])-l([[:space:]]|=|$)'; then
    ok "the command file records a label selector"
  else
    bad "the command file records a label selector (got '$CMD')"
  fi
else
  bad "the command file $COMMAND_FILE exists"
  skip "the contents of the command file (there is no $COMMAND_FILE to read)"
fi

note "A label selector is how you narrow a namespace down to the pods you"
note "actually care about before you sort by usage."
note ""
note "kubectl top pods shows current usage, which for a busy-loop container is"
note "the pod's CPU request (or the node's share) rather than a true"
note "measurement - the metrics server reports usage against the request."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c28 PASSED${X}"; else echo -e "${R}c28 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
