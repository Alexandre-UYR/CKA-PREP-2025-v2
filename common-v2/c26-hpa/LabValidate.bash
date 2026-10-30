#!/bin/bash
# Grader for c26 (Horizontal autoscaling).
#
# IMPORTANT: this checks the HPA SPEC, never the live replica count. Without a
# working metrics-server the HPA reports <unknown> for the current metric and
# never scales, even though the HPA object itself is entirely correct.
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

NS=autoscale
HPA=web-hpa
DEPLOY=web
UID_FILE=/tmp/cka-lab/c26.uid

echo "== c26: Horizontal autoscaling =="

# Read a field out of the HPA. Empty string if the HPA does not exist.
jp(){ k get hpa "$HPA" -n "$NS" -o "jsonpath=$1" 2>/dev/null; }

exists "HPA $HPA exists in namespace $NS" hpa "$HPA" -n "$NS"

# ---- it has to target the Deployment that is already there ----
eq "the HPA scaleTargetRef name is web" "$(jp '{.spec.scaleTargetRef.name}')" "web"
eq "the HPA scaleTargetRef kind is Deployment" "$(jp '{.spec.scaleTargetRef.kind}')" "Deployment"

# ---- the replica bounds ----
eq "the HPA minReplicas is 2" "$(jp '{.spec.minReplicas}')" "2"
eq "the HPA maxReplicas is 8" "$(jp '{.spec.maxReplicas}')" "8"

# ---- the CPU metric ----
eq "the HPA metric type is Resource" "$(jp '{.spec.metrics[0].type}')" "Resource"
eq "the HPA metric resource name is cpu" "$(jp '{.spec.metrics[0].resource.name}')" "cpu"
eq "the HPA metric target type is Utilization" "$(jp '{.spec.metrics[0].resource.target.type}')" "Utilization"
eq "the HPA metric target averageUtilization is 60" "$(jp '{.spec.metrics[0].resource.target.averageUtilization}')" "60"

# ---- the scaleDown stabilisation window ----
eq "the HPA scaleDown stabilizationWindowSeconds is 60" "$(jp '{.spec.behavior.scaleDown.stabilizationWindowSeconds}')" "60"

# ---- the Deployment was edited, not re-created ----
exists "the target Deployment $DEPLOY still exists" deployment "$DEPLOY" -n "$NS"
if [ -f "$UID_FILE" ]; then
  UID_BEFORE=$(tr -d '[:space:]' < "$UID_FILE" 2>/dev/null || true)
  UID_NOW=$(k -n "$NS" get deployment "$DEPLOY" -o jsonpath='{.metadata.uid}' 2>/dev/null || true)
  eq "the $DEPLOY Deployment was edited, not re-created (same UID)" "$UID_NOW" "$UID_BEFORE"
else
  skip "the $DEPLOY Deployment was edited, not re-created (no UID file at $UID_FILE)"
fi

note "The grader reads the HPA spec out of the API. It never looks at how many"
note "replicas exist: without a working metrics-server the HPA reports"
note "<unknown> for the current metric and never scales, even when the HPA"
note "object itself is entirely correct."
note ""
note "averageUtilization is a percentage of the container's CPU REQUEST (100m"
note "here), not of the limit (200m) and not of the node."
note "The stabilisation window belongs under behavior.scaleDown, as a sibling"
note "of policies - not inside it, and not under scaleUp."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c26 PASSED${X}"; else echo -e "${R}c26 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
