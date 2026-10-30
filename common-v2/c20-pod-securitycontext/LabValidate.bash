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

NS=secure
POD=restricted

echo "== c20: Run a Pod with restricted privileges =="

if ! exists "Pod $POD exists in namespace $NS" -n "$NS" pod "$POD"; then
  echo; echo -e "${R}c20 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the Pod has to actually run ----
PHASE=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null)
eq "the Pod is Running" "$PHASE" "Running"

READY=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
eq "the Pod is Ready" "$READY" "True"

# ---- pod-level securityContext ----
RUNAS=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.securityContext.runAsUser}' 2>/dev/null)
eq "the pod securityContext sets runAsUser: 1000" "$RUNAS" "1000"

NONROOT=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.securityContext.runAsNonRoot}' 2>/dev/null)
eq "the pod securityContext sets runAsNonRoot: true" "$NONROOT" "true"

# ---- container-level securityContext ----
CNAMES=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null)
nonempty "the Pod has at least one container" "$CNAMES"

POD_SECCOMP=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.securityContext.seccompProfile.type}' 2>/dev/null)
CON_SECCOMP=""
for c in $CNAMES; do
  APE=$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.containers[?(@.name==\"$c\")].securityContext.allowPrivilegeEscalation}" 2>/dev/null)
  eq "container $c sets allowPrivilegeEscalation: false" "$APE" "false"

  DROP=$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.containers[?(@.name==\"$c\")].securityContext.capabilities.drop}" 2>/dev/null)
  has "container $c drops ALL capabilities" "$DROP" "ALL"

  ADD=$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.containers[?(@.name==\"$c\")].securityContext.capabilities.add}" 2>/dev/null)
  if [ -z "$ADD" ] || [ "$ADD" = "[]" ]; then
    ok "container $c adds no capability back"
  else
    bad "container $c adds no capability back (got '$ADD')"
  fi

  CT=$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.containers[?(@.name==\"$c\")].securityContext.seccompProfile.type}" 2>/dev/null)
  CON_SECCOMP="$CON_SECCOMP $CT"
done

# ---- the seccomp profile may sit on the pod or on the container ----
CON_SECCOMP_TRIM="$(printf '%s' "$CON_SECCOMP" | sed 's/^ *//')"
SECCOMP_FOUND=0
[ "$POD_SECCOMP" = "RuntimeDefault" ] && SECCOMP_FOUND=1
case "$CON_SECCOMP_TRIM" in *RuntimeDefault*) SECCOMP_FOUND=1;; esac
if [ "$SECCOMP_FOUND" = "1" ]; then
  ok "the seccomp profile is RuntimeDefault (pod: '$POD_SECCOMP', container: '$CON_SECCOMP_TRIM')"
else
  bad "the seccomp profile is RuntimeDefault (pod: '$POD_SECCOMP', container: '$CON_SECCOMP_TRIM')"
fi

note "runAsUser, runAsNonRoot and the seccomp profile are POD-level fields;"
note "allowPrivilegeEscalation and capabilities are CONTAINER-level fields."
note "dropping ALL capabilities and then adding one back is a no-op at best."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c20 PASSED${X}"; else echo -e "${R}c20 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
