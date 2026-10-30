#!/bin/bash
# Grader for c27 (a pod that will not stay up).
#
# The fix for a CrashLoopBackOff caused by a container's securityContext is to
# delete the Pod and create it again - the field is immutable once the Pod
# exists. The grader proves the Pod was re-created by comparing its
# creationTimestamp with the one the setup recorded, and proves it is stable
# by sampling restartCount twice, ten seconds apart.
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

NS=broken
POD=worker
BEFORE_FILE=/tmp/cka-lab/c27.pod.before

echo "== c27: A pod that will not stay up =="

if exists "Pod $POD exists in namespace $NS" -n "$NS" pod "$POD"; then
  # ---- the Pod has to actually run ----
  PHASE=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null)
  eq "the Pod is Running" "$PHASE" "Running"

  RUNNING=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].state.running.startedAt}' 2>/dev/null)
  nonempty "the container is running, not waiting in CrashLoopBackOff" "$RUNNING"

  READYCOUNT=$(k -n "$NS" get pod "$POD" -o jsonpath='{range .status.containerStatuses[*]}{.ready}{"\n"}{end}' 2>/dev/null | grep -c '^true$' || true)
  eq "the Pod has exactly 1 ready container" "$READYCOUNT" "1"

  # ---- the read-only root filesystem has to be gone ----
  RO=$(k -n "$NS" get pod "$POD" -o jsonpath='{range .spec.containers[*]}{.name}={.securityContext.readOnlyRootFilesystem}{"\n"}{end}' 2>/dev/null)
  if printf '%s\n' "$RO" | grep -q '=true$'; then
    bad "no container sets securityContext.readOnlyRootFilesystem: true (got '$RO')"
  else
    ok "no container sets securityContext.readOnlyRootFilesystem: true"
  fi

  # ---- the Pod has to be a NEW Pod, not the one the setup created ----
  if [ -f "$BEFORE_FILE" ]; then
    BEFORE=$(tr -d '[:space:]' < "$BEFORE_FILE" 2>/dev/null || true)
    BEFORE_N=$(printf '%s' "$BEFORE" | sed 's/\.[0-9]*Z$/Z/')
    NOW=$(k -n "$NS" get pod "$POD" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || true)
    NOW_N=$(printf '%s' "$NOW" | sed 's/\.[0-9]*Z$/Z/')
    if [ -n "$BEFORE_N" ] && [ -n "$NOW_N" ] && [ "$NOW_N" \> "$BEFORE_N" ]; then
      ok "the Pod was re-created (creationTimestamp '$NOW' is newer than the setup's '$BEFORE')"
    else
      bad "the Pod was re-created (creationTimestamp '$NOW' is not newer than the setup's '$BEFORE')"
    fi
  else
    skip "the Pod was re-created (no timestamp file at $BEFORE_FILE)"
  fi

  # ---- and it has to stay up: restartCount must stop climbing ----
  R1=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || true)
  sleep 10
  R2=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || true)
  if [ -n "$R1" ] && [ -n "$R2" ] && [ "$R1" = "$R2" ]; then
    ok "the container's restartCount is stable across 10 seconds (stayed at $R1)"
  else
    bad "the container's restartCount is stable across 10 seconds (got '$R1' then '$R2')"
  fi
else
  skip "the rest of the checks (no Pod $POD in namespace $NS to inspect)"
fi

note "A container's securityContext is immutable once the Pod exists, so the"
note "fix is to delete the Pod and re-create it - kubectl patch will refuse."
note ""
note "readOnlyRootFilesystem: true makes any write outside a mounted volume"
note "fail, which is why the fix is either to mount a volume at /data or to"
note "allow the write."
note ""
note "A Pod whose container is crash-looping still has phase Running. The"
note "signal is in the container status: state.waiting.reason says"
note "CrashLoopBackOff, and the restartCount keeps climbing."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c27 PASSED${X}"; else echo -e "${R}c27 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
