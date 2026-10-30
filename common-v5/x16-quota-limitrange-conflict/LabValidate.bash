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

# cpu is compared in milli-units, memory in MiB.
to_milli(){ printf '%s\n' "$1" | awk '{ s=$0; if (s ~ /m$/) { sub(/m$/,"",s); v=s } else { v=s*1000 } printf "%d", v }'; }
to_mib(){ printf '%s\n' "$1" | awk '{ s=$0; if (s ~ /Mi$/) { sub(/Mi$/,"",s); v=s } else if (s ~ /Gi$/) { sub(/Gi$/,"",s); v=s*1024 } else if (s ~ /Ki$/) { sub(/Ki$/,"",s); v=s/1024 } else { v=s/1048576 } printf "%d", v }'; }

NS=conflict
POD=fits
QUOTA=tight
LR=defaults
LABDIR=/tmp/cka-lab
BEFORE="$LABDIR/x16.before"

echo "== x16: Two rules that contradict each other =="

if ! exists "namespace $NS exists" namespace "$NS"; then
  echo; echo -e "${R}x16 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---------------------------------------------------------------------------
# the two objects must still be there, and must not have been changed
# ---------------------------------------------------------------------------
before_val(){ grep "^$1=" "$BEFORE" 2>/dev/null | head -1 | cut -d= -f2- ; }

if [ ! -f "$BEFORE" ]; then
  bad "the ResourceQuota $QUOTA is unchanged (no spec was recorded at setup)"
  bad "the LimitRange $LR is unchanged (no spec was recorded at setup)"
else
  # ---- the ResourceQuota ----
  QC=$(k -n "$NS" get resourcequota "$QUOTA" -o jsonpath='{.spec.hard.limits\.cpu}' 2>/dev/null)
  QM=$(k -n "$NS" get resourcequota "$QUOTA" -o jsonpath='{.spec.hard.limits\.memory}' 2>/dev/null)
  QR_C=$(k -n "$NS" get resourcequota "$QUOTA" -o jsonpath='{.spec.hard.requests\.cpu}' 2>/dev/null)
  QR_M=$(k -n "$NS" get resourcequota "$QUOTA" -o jsonpath='{.spec.hard.requests\.memory}' 2>/dev/null)

  B_C=$(before_val quota.hard.limits.cpu)
  B_M=$(before_val quota.hard.limits.memory)
  B_RC=$(before_val quota.hard.requests.cpu)
  B_RM=$(before_val quota.hard.requests.memory)

  QUOTA_SAME=1
  [ -z "$QC" ]  && QUOTA_SAME=0
  [ -z "$QM" ]  && QUOTA_SAME=0
  [ -z "$QR_C" ] && QUOTA_SAME=0
  [ -z "$QR_M" ] && QUOTA_SAME=0
  if [ "$QUOTA_SAME" = "1" ]; then
    if [ "$(to_milli "$QC")" = "$(to_milli "$B_C")" ] && [ "$(to_mib "$QM")" = "$(to_mib "$B_M")" ] \
       && [ "$(to_milli "$QR_C")" = "$(to_milli "$B_RC")" ] && [ "$(to_mib "$QR_M")" = "$(to_mib "$B_RM")" ]; then
      ok "the ResourceQuota $QUOTA is unchanged (limits.cpu $QC, limits.memory $QM, requests.cpu $QR_C, requests.memory $QR_M)"
    else
      bad "the ResourceQuota $QUOTA is unchanged (it is now limits.cpu $QC, limits.memory $QM, requests.cpu $QR_C, requests.memory $QR_M - it was limits.cpu $B_C, limits.memory $B_M, requests.cpu $B_RC, requests.memory $B_RM)"
    fi
  else
    bad "the ResourceQuota $QUOTA is unchanged (it has been deleted, or one of its hard values is gone)"
  fi

  # ---- the LimitRange ----
  LT=$(k -n "$NS" get limitrange "$LR" -o jsonpath='{.spec.limits[0].type}' 2>/dev/null)
  LD_C=$(k -n "$NS" get limitrange "$LR" -o jsonpath='{.spec.limits[0].default.cpu}' 2>/dev/null)
  LD_M=$(k -n "$NS" get limitrange "$LR" -o jsonpath='{.spec.limits[0].default.memory}' 2>/dev/null)
  LDR_C=$(k -n "$NS" get limitrange "$LR" -o jsonpath='{.spec.limits[0].defaultRequest.cpu}' 2>/dev/null)
  LDR_M=$(k -n "$NS" get limitrange "$LR" -o jsonpath='{.spec.limits[0].defaultRequest.memory}' 2>/dev/null)

  B_LT=$(before_val limitrange.type)
  B_LD_C=$(before_val limitrange.default.cpu)
  B_LD_M=$(before_val limitrange.default.memory)
  B_LDR_C=$(before_val limitrange.defaultRequest.cpu)
  B_LDR_M=$(before_val limitrange.defaultRequest.memory)

  LR_SAME=1
  [ -z "$LT" ]    && LR_SAME=0
  [ -z "$LD_C" ]  && LR_SAME=0
  [ -z "$LD_M" ]  && LR_SAME=0
  [ -z "$LDR_C" ] && LR_SAME=0
  [ -z "$LDR_M" ] && LR_SAME=0
  if [ "$LR_SAME" = "1" ]; then
    if [ "$LT" = "$B_LT" ] && [ "$(to_milli "$LD_C")" = "$(to_milli "$B_LD_C")" ] \
       && [ "$(to_mib "$LD_M")" = "$(to_mib "$B_LD_M")" ] && [ "$(to_milli "$LDR_C")" = "$(to_milli "$B_LDR_C")" ] \
       && [ "$(to_mib "$LDR_M")" = "$(to_mib "$B_LDR_M")" ]; then
      ok "the LimitRange $LR is unchanged (type $LT, default cpu $LD_C memory $LD_M, defaultRequest cpu $LDR_C memory $LDR_M)"
    else
      bad "the LimitRange $LR is unchanged (it is now type $LT, default cpu $LD_C memory $LD_M, defaultRequest cpu $LDR_C memory $LDR_M - it was type $B_LT, default cpu $B_LD_C memory $B_LD_M, defaultRequest cpu $B_LDR_C memory $B_LDR_M)"
    fi
  else
    bad "the LimitRange $LR is unchanged (it has been deleted, or one of its values is gone)"
  fi
fi

# ---------------------------------------------------------------------------
# the Pod
# ---------------------------------------------------------------------------
if ! exists "Pod $POD exists in namespace $NS" -n "$NS" pod "$POD"; then
  bad "the Pod $POD is Running"
  bad "the Pod $POD has a ready container"
  bad "the Pod $POD states requests.cpu, requests.memory, limits.cpu and limits.memory"
  bad "the Pod $POD's requests and limits fit inside the quota"
  bad "the quota's status.used reflects the Pod $POD"
  echo; echo -e "${R}x16 FAILED ($FAILS checks)${X}"; exit 1
fi

PHASE=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null)
eq "the Pod $POD is Running" "$PHASE" "Running"

READY=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
eq "the Pod $POD has a ready container" "$READY" "true"

# ---- every field stated ----
RC=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[0].resources.requests\.cpu}' 2>/dev/null)
RM=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[0].resources.requests\.memory}' 2>/dev/null)
LC=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[0].resources.limits\.cpu}' 2>/dev/null)
LM=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[0].resources.limits\.memory}' 2>/dev/null)

MISSING=""
[ -z "$RC" ] && MISSING="$MISSING requests.cpu"
[ -z "$RM" ] && MISSING="$MISSING requests.memory"
[ -z "$LC" ] && MISSING="$MISSING limits.cpu"
[ -z "$LM" ] && MISSING="$MISSING limits.memory"
if [ -z "$MISSING" ]; then
  ok "the Pod $POD states requests.cpu, requests.memory, limits.cpu and limits.memory"
else
  bad "the Pod $POD states requests.cpu, requests.memory, limits.cpu and limits.memory (missing:$MISSING)"
fi

# ---- and every field inside the quota ----
# The quota's own hard values, read live.
H_LC=$(k -n "$NS" get resourcequota "$QUOTA" -o jsonpath='{.spec.hard.limits\.cpu}' 2>/dev/null)
H_LM=$(k -n "$NS" get resourcequota "$QUOTA" -o jsonpath='{.spec.hard.limits\.memory}' 2>/dev/null)
H_RC=$(k -n "$NS" get resourcequota "$QUOTA" -o jsonpath='{.spec.hard.requests\.cpu}' 2>/dev/null)
H_RM=$(k -n "$NS" get resourcequota "$QUOTA" -o jsonpath='{.spec.hard.requests\.memory}' 2>/dev/null)

OVER=""
if [ -n "$RC" ] && [ -n "$H_RC" ] && [ "$(to_milli "$RC")" -gt "$(to_milli "$H_RC")" ]; then
  OVER="$OVER requests.cpu $RC > $H_RC"
fi
if [ -n "$RM" ] && [ -n "$H_RM" ] && [ "$(to_mib "$RM")" -gt "$(to_mib "$H_RM")" ]; then
  OVER="$OVER requests.memory $RM > $H_RM"
fi
if [ -n "$LC" ] && [ -n "$H_LC" ] && [ "$(to_milli "$LC")" -gt "$(to_milli "$H_LC")" ]; then
  OVER="$OVER limits.cpu $LC > $H_LC"
fi
if [ -n "$LM" ] && [ -n "$H_LM" ] && [ "$(to_mib "$LM")" -gt "$(to_mib "$H_LM")" ]; then
  OVER="$OVER limits.memory $LM > $H_LM"
fi
if [ -z "$OVER" ] && [ -n "$RC" ] && [ -n "$RM" ] && [ -n "$LC" ] && [ -n "$LM" ]; then
  ok "the Pod $POD's requests and limits fit inside the quota (requests $RC/$RM, limits $LC/$LM)"
else
  bad "the Pod $POD's requests and limits fit inside the quota (over:$OVER - the quota allows requests $H_RC/$H_RM and limits $H_LC/$H_LM)"
fi

# ---- the quota's usage accounts for the Pod ----
USED_C=""
USED_M=""
i=0
while [ "$i" -lt 30 ]; do
  USED_C=$(k -n "$NS" get resourcequota "$QUOTA" -o jsonpath='{.status.used.requests\.cpu}' 2>/dev/null)
  USED_M=$(k -n "$NS" get resourcequota "$QUOTA" -o jsonpath='{.status.used.requests\.memory}' 2>/dev/null)
  if [ -n "$USED_C" ] && [ -n "$USED_M" ]; then break; fi
  sleep 2
  i=$((i+2))
done
if [ -z "$USED_C" ] || [ -z "$USED_M" ]; then
  bad "the quota's status.used reflects the Pod $POD (status.used is empty)"
elif [ -z "$RC" ] || [ -z "$RM" ]; then
  bad "the quota's status.used reflects the Pod $POD (the Pod states no requests)"
elif [ "$(to_milli "$USED_C")" -ge "$(to_milli "$RC")" ] && [ "$(to_mib "$USED_M")" -ge "$(to_mib "$RM")" ]; then
  ok "the quota's status.used reflects the Pod $POD (used requests.cpu $USED_C, requests.memory $USED_M)"
else
  bad "the quota's status.used reflects the Pod $POD (used requests.cpu $USED_C, requests.memory $USED_M - the Pod asks for $RC/$RM)"
fi

note "A ResourceQuota is enforced at admission time and a LimitRange is enforced"
note "at admission time too: one sets DEFAULTS, the other sets CEILINGS. When the"
note "defaults are larger than the ceiling nothing can be created at all. The two"
note "objects are not aware of each other - only the API server puts them together."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}x16 PASSED${X}"; else echo -e "${R}x16 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
