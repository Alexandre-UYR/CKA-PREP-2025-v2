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

NS=autoscale
DEP=hpa-example
SVC=hpa-example
HPA=hpa
LABDIR=/tmp/cka-lab

echo "== x14: Make it work harder, then watch it =="

if ! exists "namespace $NS exists" namespace "$NS"; then
  echo; echo -e "${R}x14 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---------------------------------------------------------------------------
# 1. a metrics server
# ---------------------------------------------------------------------------
MS_DEPLOY=$(k get deploy -n kube-system -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
            | grep -i 'metrics-server' | head -1) || MS_DEPLOY=""
if [ -n "$MS_DEPLOY" ]; then
  ok "a metrics-server Deployment is installed in kube-system ($MS_DEPLOY)"
else
  bad "a metrics-server Deployment is installed in kube-system (none found)"
fi

# Does the metrics API answer? This is what the autoscaler actually reads.
METRICS_OK=0
METRICS_OUT=$(k get --raw /apis/metrics.k8s.io/v1beta1/pods --request-timeout=10s 2>/dev/null) || METRICS_OUT=""
case "$METRICS_OUT" in
  *'"items"'*) METRICS_OK=1 ;;
esac

if [ "$METRICS_OK" = "1" ]; then
  ok "the metrics API answers (metrics.k8s.io/v1beta1)"
else
  skip "the metrics API does not answer yet (metrics.k8s.io/v1beta1)"
fi

# ---------------------------------------------------------------------------
# 2. the HorizontalPodAutoscaler
# ---------------------------------------------------------------------------
if exists "HorizontalPodAutoscaler $HPA exists in namespace $NS" -n "$NS" hpa "$HPA"; then
  TARGET_NAME=$(k -n "$NS" get hpa "$HPA" -o jsonpath='{.spec.scaleTargetRef.name}' 2>/dev/null)
  eq "the HPA's scaleTargetRef.name is $DEP" "$TARGET_NAME" "$DEP"

  TARGET_KIND=$(k -n "$NS" get hpa "$HPA" -o jsonpath='{.spec.scaleTargetRef.kind}' 2>/dev/null)
  eq "the HPA's scaleTargetRef.kind is Deployment" "$TARGET_KIND" "Deployment"

  MINREP=$(k -n "$NS" get hpa "$HPA" -o jsonpath='{.spec.minReplicas}' 2>/dev/null)
  eq "the HPA's minReplicas is 1" "$MINREP" "1"

  MAXREP=$(k -n "$NS" get hpa "$HPA" -o jsonpath='{.spec.maxReplicas}' 2>/dev/null)
  eq "the HPA's maxReplicas is 10" "$MAXREP" "10"

  MNAME=$(k -n "$NS" get hpa "$HPA" -o jsonpath='{.spec.metrics[0].resource.name}' 2>/dev/null)
  eq "the HPA's metric resource is cpu" "$MNAME" "cpu"

  MTYPE=$(k -n "$NS" get hpa "$HPA" -o jsonpath='{.spec.metrics[0].resource.target.type}' 2>/dev/null)
  eq "the HPA's target type is Utilization" "$MTYPE" "Utilization"

  MAVG=$(k -n "$NS" get hpa "$HPA" -o jsonpath='{.spec.metrics[0].resource.target.averageUtilization}' 2>/dev/null)
  eq "the HPA's target averageUtilization is 50" "$MAVG" "50"
else
  bad "HorizontalPodAutoscaler $HPA exists in namespace $NS"
  bad "the HPA's scaleTargetRef.name is $DEP"
  bad "the HPA's scaleTargetRef.kind is Deployment"
  bad "the HPA's minReplicas is 1"
  bad "the HPA's maxReplicas is 10"
  bad "the HPA's metric resource is cpu"
  bad "the HPA's target type is Utilization"
  bad "the HPA's target averageUtilization is 50"
fi

# ---------------------------------------------------------------------------
# 3. the load generator
# ---------------------------------------------------------------------------
LOADGEN=""
for p in $(k -n "$NS" get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
  SPEC=$(k -n "$NS" get pod "$p" -o jsonpath='{range .spec.containers[*]}{.command}{" "}{.args}{"\n"}{end}' 2>/dev/null)
  case "$SPEC" in
    *wget*)
      case "$SPEC" in
        *"$SVC"*) LOADGEN="$p"; break ;;
      esac
      ;;
  esac
done

if [ -n "$LOADGEN" ]; then
  ok "a load generator Pod is running a loop against the Service ($LOADGEN)"
  SPEC=$(k -n "$NS" get pod "$LOADGEN" -o jsonpath='{range .spec.containers[*]}{.command}{" "}{.args}{"\n"}{end}' 2>/dev/null)
  case "$SPEC" in
    *while*|*for*|*do*) ok "the load generator really is a loop (it contains a while/for/do)" ;;
    *) bad "the load generator really is a loop (it contains a while/for/do)" ;;
  esac
  PHASE=$(k -n "$NS" get pod "$LOADGEN" -o jsonpath='{.status.phase}' 2>/dev/null)
  eq "the load generator Pod is Running" "$PHASE" "Running"
else
  bad "a load generator Pod is running a loop against the Service (no pod in $NS runs wget against $SVC)"
  bad "the load generator really is a loop (it contains a while/for/do)"
  bad "the load generator Pod is Running"
fi

# ---------------------------------------------------------------------------
# 4. the Deployment scaled up
# ---------------------------------------------------------------------------
if [ "$METRICS_OK" != "1" ]; then
  skip "the Deployment scaled above 1 replica (the metrics API is not answering, so the autoscaler has nothing to act on)"
elif [ -z "$LOADGEN" ]; then
  skip "the Deployment scaled above 1 replica (no load generator is running, so there is no load to scale for)"
else
  echo "Waiting up to 3 minutes for the autoscaler to scale the Deployment..."
  REPS=""
  i=0
  while [ "$i" -lt 180 ]; do
    REPS=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.replicas}' 2>/dev/null) || REPS=""
    case "$REPS" in
      ''|*[!0-9]*) ;;
      *) [ "$REPS" -gt 1 ] && break ;;
    esac
    sleep 5
    i=$((i+5))
  done
  case "$REPS" in
    ''|*[!0-9]*) ;;
    *)
      if [ "$REPS" -gt 1 ]; then
        ok "the Deployment scaled up (spec.replicas is $REPS)"
      else
        bad "the Deployment scaled up (spec.replicas is still $REPS)"
      fi
      ;;
  esac
fi

note "The HPA's CPU target is a percentage of the container's CPU REQUEST."
note "50% of 200m is 100m of CPU per pod, averaged across the pods of the"
note "Deployment - not a percentage of the limit, and not a percentage of the node."
note "The autoscaler cannot act at all until the metrics API is answering."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}x14 PASSED${X}"; else echo -e "${R}x14 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
