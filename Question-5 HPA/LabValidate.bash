#!/bin/bash
# Grader for Question 5 (HPA).
#
# IMPORTANT: this checks the HPA SPEC, not the live replica count. Without a
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

# Read a field out of the HPA. Empty string if the HPA does not exist.
jp(){ k get hpa apache-server -n autoscale -o "jsonpath=$1" 2>/dev/null; }

exists "HPA apache-server exists in namespace autoscale" hpa apache-server -n autoscale

# 1. The HPA must target the existing deployment called apache-deployment
eq "HPA scaleTargetRef.name is apache-deployment" "$(jp '{.spec.scaleTargetRef.name}')" "apache-deployment"
eq "HPA scaleTargetRef.kind is Deployment" "$(jp '{.spec.scaleTargetRef.kind}')" "Deployment"
eq "HPA scaleTargetRef.apiVersion is apps/v1" "$(jp '{.spec.scaleTargetRef.apiVersion}')" "apps/v1"

# 2. Target 50% CPU usage per Pod
eq "HPA metric type is Resource" "$(jp '{.spec.metrics[0].type}')" "Resource"
eq "HPA metric resource.name is cpu" "$(jp '{.spec.metrics[0].resource.name}')" "cpu"
eq "HPA metric target type is Utilization" "$(jp '{.spec.metrics[0].resource.target.type}')" "Utilization"
eq "HPA metric target averageUtilization is 50" "$(jp '{.spec.metrics[0].resource.target.averageUtilization}')" "50"

# 3. Minimum of 1 pod and a maximum of 4 pods
eq "HPA minReplicas is 1" "$(jp '{.spec.minReplicas}')" "1"
eq "HPA maxReplicas is 4" "$(jp '{.spec.maxReplicas}')" "4"

# 4. Downscale stabilization window of 30 seconds
eq "HPA scaleDown stabilizationWindowSeconds is 30" "$(jp '{.spec.behavior.scaleDown.stabilizationWindowSeconds}')" "30"

if [ "$FAILS" -eq 0 ]; then echo -e "${G}Q5 PASSED${X}"; else echo -e "${R}Q5 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
