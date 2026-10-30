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

# ---- runAsUser and runAsNonRoot ----
# Both may be set on the Pod's securityContext or on a container's. The Pod
# level applies to every container that does not override it, so accept either.
POD_RUNAS=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.securityContext.runAsUser}' 2>/dev/null)
POD_NONROOT=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.securityContext.runAsNonRoot}' 2>/dev/null)

RUNAS="$POD_RUNAS"; V_RUNAS=""; SRC_RUNAS="pod"
[ -n "$POD_RUNAS" ] || SRC_RUNAS="container"
NONROOT="$POD_NONROOT"; V_NONROOT=""; SRC_NONROOT="pod"
[ -n "$POD_NONROOT" ] || SRC_NONROOT="container"

# ---- container-level securityContext ----
CNAMES=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null)
nonempty "the Pod has at least one container" "$CNAMES"

POD_SECCOMP=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.securityContext.seccompProfile.type}' 2>/dev/null)
NC=$(printf '%s' "$CNAMES" | wc -w | tr -d ' ')
CON_SECCOMP=""; V_SEC=""

for c in $CNAMES; do
  # A container-level runAsUser / runAsNonRoot is only consulted when the Pod
  # level does not set it.
  if [ -z "$POD_RUNAS" ]; then
    v=$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.containers[?(@.name==\"$c\")].securityContext.runAsUser}" 2>/dev/null)
    [ -n "$v" ] && { RUNAS="$v"; V_RUNAS="$V_RUNAS $c=$v"; }
  fi
  if [ -z "$POD_NONROOT" ]; then
    v=$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.containers[?(@.name==\"$c\")].securityContext.runAsNonRoot}" 2>/dev/null)
    [ -n "$v" ] && { NONROOT="$v"; V_NONROOT="$V_NONROOT $c=$v"; }
  fi

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
  if [ "$CT" = "RuntimeDefault" ]; then V_SEC="$V_SEC 1"; else V_SEC="$V_SEC 0"; fi
done

eq "runAsUser is 1000 (set at the $SRC_RUNAS level)" "$RUNAS" "1000"
eq "runAsNonRoot is true (set at the $SRC_NONROOT level)" "$NONROOT" "true"

# ---- the seccomp profile may sit on the pod or on the container ----
CON_SECCOMP_TRIM="$(printf '%s' "$CON_SECCOMP" | sed 's/^ *//')"
if [ "$POD_SECCOMP" = "RuntimeDefault" ]; then SECCOMP_FOUND=$NC; else SECCOMP_FOUND=$(printf '%s' "$V_SEC" | tr ' ' '\n' | grep -c '^1$'); fi
if [ "$SECCOMP_FOUND" = "$NC" ] && [ "$NC" -gt 0 ]; then
  ok "the seccomp profile is RuntimeDefault (pod: '$POD_SECCOMP', container: '$CON_SECCOMP_TRIM')"
else
  bad "the seccomp profile is RuntimeDefault (pod: '$POD_SECCOMP', container: '$CON_SECCOMP_TRIM')"
fi

note "runAsUser, runAsNonRoot and the seccomp profile may be set on the Pod's"
note "securityContext or on a container's - the Pod level applies to every"
note "container that does not override it. allowPrivilegeEscalation and"
note "capabilities are container-level fields."
note "dropping ALL capabilities and then adding one back is a no-op at best."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c20 PASSED${X}"; else echo -e "${R}c20 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
