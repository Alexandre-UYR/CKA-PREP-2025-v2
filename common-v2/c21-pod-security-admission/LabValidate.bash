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

NS=psa-test
POD=compliant
PROBE=psa-violation-probe

echo "== c21: Enforce the restricted Pod Security Standard =="

if ! exists "namespace $NS exists" ns "$NS"; then
  echo; echo -e "${R}c21 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- 1. the namespace must enforce the restricted profile ----
ENFORCE=$(k get ns "$NS" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null)
eq "the namespace ENFORCES the restricted Pod Security Standard" "$ENFORCE" "restricted"

EV=$(k get ns "$NS" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce-version}' 2>/dev/null)
if [ -n "$EV" ]; then
  case "$EV" in
    latest|v1.*) ok "the enforce-version label names a known version ('$EV')";;
    *) bad "the enforce-version label names a known version (got '$EV')";;
  esac
else
  note "no pod-security.kubernetes.io/enforce-version label - the API server"
  note "falls back to its own default, which the task allows."
fi

# ---- 2. the Pod has to satisfy the profile ----
if k -n "$NS" get pod "$POD" >/dev/null 2>&1; then
  ok "Pod $POD exists in namespace $NS"

  PHASE=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null)
  eq "the Pod $POD is Running" "$PHASE" "Running"

  READY=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  eq "the Pod $POD is Ready" "$READY" "True"

  # the restricted profile can be satisfied at pod level or per container
  P_NONROOT=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.securityContext.runAsNonRoot}' 2>/dev/null)
  P_RUNAS=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.securityContext.runAsUser}' 2>/dev/null)
  P_SECCOMP=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.securityContext.seccompProfile.type}' 2>/dev/null)

  CNAMES=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null)
  NC=$(printf '%s' "$CNAMES" | wc -w | tr -d ' ')
  # one verdict per container, so that a single bad container cannot hide
  V_NR=""; V_RUNAS=""; V_APE=""; V_DROP=""; V_SEC=""
  for c in $CNAMES; do
    v=$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.containers[?(@.name==\"$c\")].securityContext.runAsNonRoot}" 2>/dev/null)
    if [ "$v" = "true" ]; then V_NR="$V_NR 1"; else V_NR="$V_NR 0"; fi
    v=$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.containers[?(@.name==\"$c\")].securityContext.runAsUser}" 2>/dev/null)
    V_RUNAS="$V_RUNAS $v"
    v=$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.containers[?(@.name==\"$c\")].securityContext.allowPrivilegeEscalation}" 2>/dev/null)
    if [ "$v" = "false" ]; then V_APE="$V_APE 1"; else V_APE="$V_APE 0"; fi
    v=$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.containers[?(@.name==\"$c\")].securityContext.capabilities.drop}" 2>/dev/null)
    case "$v" in *ALL*) V_DROP="$V_DROP 1";; *) V_DROP="$V_DROP 0";; esac
    v=$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.containers[?(@.name==\"$c\")].securityContext.seccompProfile.type}" 2>/dev/null)
    if [ "$v" = "RuntimeDefault" ]; then V_SEC="$V_SEC 1"; else V_SEC="$V_SEC 0"; fi
  done

  # a pod-level field covers every container; without it, every container has
  # to carry the field itself
  if [ "$P_NONROOT" = "true" ]; then NR_OK=$NC; else NR_OK=$(printf '%s' "$V_NR" | tr ' ' '\n' | grep -c '^1$'); fi
  if [ "$NR_OK" = "$NC" ] && [ "$NC" -gt 0 ]; then
    ok "runAsNonRoot is true for the Pod (pod: '$P_NONROOT', containers: $V_NR)"
  else
    bad "runAsNonRoot is true for the Pod (pod: '$P_NONROOT', containers: $V_NR)"
  fi

  if [ -n "$P_RUNAS" ]; then
    RUNAS="$P_RUNAS"
    RUNAS_OK=$NC
    [ "$RUNAS" = "0" ] && RUNAS_OK=0
  else
    RUNAS="$(printf '%s' "$V_RUNAS" | tr ' ' '\n' | grep -v '^$' | head -1)"
    RUNAS_OK=$(printf '%s' "$V_RUNAS" | tr ' ' '\n' | grep -v '^$' | grep -vc '^0$')
    [ -n "$RUNAS" ] || RUNAS_OK=0
  fi
  nonempty "a runAsUser is set on the Pod" "$RUNAS"
  if [ "$RUNAS_OK" = "$NC" ] && [ "$NC" -gt 0 ]; then
    ok "the runAsUser is not 0 (pod: '$P_RUNAS', containers: $V_RUNAS)"
  else
    bad "the runAsUser is not 0 (pod: '$P_RUNAS', containers: $V_RUNAS)"
  fi

  if [ "$(printf '%s' "$V_APE" | tr ' ' '\n' | grep -c '^1$')" = "$NC" ] && [ "$NC" -gt 0 ]; then
    ok "every container sets allowPrivilegeEscalation: false (containers: $V_APE)"
  else
    bad "every container sets allowPrivilegeEscalation: false (containers: $V_APE)"
  fi

  if [ "$P_SECCOMP" = "RuntimeDefault" ]; then SEC_OK=$NC; else SEC_OK=$(printf '%s' "$V_SEC" | tr ' ' '\n' | grep -c '^1$'); fi
  if [ "$SEC_OK" = "$NC" ] && [ "$NC" -gt 0 ]; then
    ok "the seccomp profile is RuntimeDefault (pod: '$P_SECCOMP', containers: $V_SEC)"
  else
    bad "the seccomp profile is RuntimeDefault (pod: '$P_SECCOMP', containers: $V_SEC)"
  fi

  if [ "$(printf '%s' "$V_DROP" | tr ' ' '\n' | grep -c '^1$')" = "$NC" ] && [ "$NC" -gt 0 ]; then
    ok "every container drops ALL capabilities (containers: $V_DROP)"
  else
    bad "every container drops ALL capabilities (containers: $V_DROP)"
  fi
else
  bad "Pod $POD exists in namespace $NS"
fi

# ---- 3. live check: the API server must REJECT a Pod that violates the profile ----
PROBE_OUT=$(k create -f - 2>&1 <<PROBE_EOF
apiVersion: v1
kind: Pod
metadata:
  name: $PROBE
  namespace: $NS
spec:
  securityContext:
    runAsUser: 0
  containers:
    - name: probe
      image: busybox:stable
      command: ["sh", "-c", "sleep 30"]
PROBE_EOF
)
PROBE_RC=$?

if [ "$PROBE_RC" -eq 0 ]; then
  bad "the API server REJECTS a Pod that violates the restricted standard (it accepted $PROBE)"
  k delete pod "$PROBE" -n "$NS" --ignore-not-found --timeout=30s >/dev/null 2>&1
else
  ok "the API server REJECTS a Pod that violates the restricted standard"
  REASON="$(printf '%s' "$PROBE_OUT" | grep -iE 'forbidden|podsecurity' | head -1)"
  if [ -n "$REASON" ]; then
    note "$(printf '%s' "$REASON" | cut -c1-160)"
  fi
fi

note "Pod Security Admission is the API server refusing the request, so a"
note "namespace that is merely labelled but not enforced accepts the Pod."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c21 PASSED${X}"; else echo -e "${R}c21 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
