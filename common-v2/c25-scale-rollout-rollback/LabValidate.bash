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

NS=release
DEP=api
UIDFILE=/tmp/cka-lab/c25.uid

echo "== c25: Scale, update, roll back =="

# Give the last rollout a chance to finish before anything is measured.
k -n "$NS" rollout status deploy/"$DEP" --timeout=60s >/dev/null 2>&1 || true

if exists "Deployment $DEP exists in namespace $NS" -n "$NS" deploy "$DEP"; then
  # ---- it was edited, not re-created ----
  CUR_UID=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.metadata.uid}' 2>/dev/null)
  if [ -f "$UIDFILE" ]; then
    REC_UID=$(tr -d '[:space:]' < "$UIDFILE")
    eq "the Deployment was edited, not deleted and re-created (its UID is unchanged)" "$CUR_UID" "$REC_UID"
  else
    skip "the UID check (the state file $UIDFILE is missing - run LabSetUp.bash first)"
  fi

  # ---- back to 2 replicas ----
  eq "the Deployment has 2 replicas" \
    "$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.replicas}' 2>/dev/null)" "2"

  eq "the Deployment has 2 ready replicas" \
    "$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" "2"

  # ---- the image is back where it started ----
  eq "the container image is back to nginx:1.25" \
    "$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.containers[*].image}' 2>/dev/null)" "nginx:1.25"

  # ---- the revision history ----
  HIST=$(k -n "$NS" rollout history deploy/"$DEP" 2>/dev/null)
  REVS=$(printf '%s\n' "$HIST" | grep -cE '^[[:space:]]*[0-9]+([.]|[[:space:]])' || true)
  if [ "${REVS:-0}" -eq 0 ] 2>/dev/null; then
    # Fall back to the ReplicaSets the Deployment owns.
    REVS=$(k -n "$NS" get rs -l app=api -o jsonpath='{range .items[*]}{.metadata.annotations.deployment\.kubernetes\.io/revision}{"\n"}{end}' 2>/dev/null | grep -c '[0-9]' || true)
  fi
  case "${REVS:-0}" in
    ''|*[!0-9]*) REVS=0 ;;
  esac
  if [ "$REVS" -ge 3 ]; then
    ok "the rollout history has at least 3 revisions (found $REVS)"
  else
    bad "the rollout history has at least 3 revisions (found $REVS)"
  fi
else
  skip "the replica / image / UID / history checks (Deployment $DEP is missing from $NS)"
fi

note "kubectl rollout undo restores the previous REVISION, so it undoes the"
note "last change and not the one before it. A rollback creates a new revision"
note "rather than deleting the bad one, and it does not undo a scale."
note "That is why the task asks for the scale back to 2 explicitly."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c25 PASSED${X}"; else echo -e "${R}c25 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
