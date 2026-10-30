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

NS=edge
DEP=catalog
SVC=catalog-svc
LIVE=cka-live-check

echo "== w19: Reachable, but only once it is ready =="

# ---- the pre-state ----
exists "Deployment $DEP exists in namespace $NS" -n "$NS" deploy "$DEP"

# ---- 2. the readiness probe, on the pod template ----
PROBE=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}' 2>/dev/null)
nonempty "the pod template has a readiness probe" "$PROBE"

PPATH=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.path}' 2>/dev/null)
eq "the readiness probe's httpGet path is '/'" "$PPATH" "/"

PPORT=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.port}' 2>/dev/null)
eq "the readiness probe's httpGet port is 80" "$PPORT" "80"

PDELAY=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.initialDelaySeconds}' 2>/dev/null)
eq "the readiness probe's initialDelaySeconds is 2" "$PDELAY" "2"

PPERIOD=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.periodSeconds}' 2>/dev/null)
eq "the readiness probe's periodSeconds is 5" "$PPERIOD" "5"

# ---- 1. the Service ----
if k -n "$NS" get svc "$SVC" >/dev/null 2>&1; then
  ok "Service $SVC exists in namespace $NS"
else
  bad "Service $SVC exists in namespace $NS (not found)"
fi

TYPE=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.type}' 2>/dev/null)
eq "the Service is of type NodePort" "$TYPE" "NodePort"

NP=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
eq "the Service's nodePort is 30080" "$NP" "30080"

PPORT=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
eq "the Service's port is 80" "$PPORT" "80"

TPORT=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)
eq "the Service's targetPort is 80" "$TPORT" "80"

# ---- the selector has to match the pods' labels ----
SELCOUNT=$(k -n "$NS" get svc "$SVC" -o go-template='{{len .spec.selector}}' 2>/dev/null)
if [ "${SELCOUNT:-0}" -ge 1 ] 2>/dev/null; then
  ok "the Service has a selector"
else
  bad "the Service has a selector (got '${SELCOUNT:-?}')"
fi

SEL=$(k -n "$NS" get svc "$SVC" -o go-template='{{range $k, $v := .spec.selector}}{{$k}}={{$v}} {{end}}' 2>/dev/null)
for entry in $SEL; do
  KEY=${entry%%=*}
  VAL=${entry#*=}
  PODLABEL=$(k -n "$NS" get deploy "$DEP" -o jsonpath="{.spec.template.metadata.labels.$KEY}" 2>/dev/null)
  eq "the Service selector '$KEY=$VAL' matches the pods' label" "$PODLABEL" "$VAL"
done

# ---- the endpoints and the ready replicas ----
EP=0
for i in $(seq 1 15); do
  EP=$(k -n "$NS" get endpoints "$SVC" -o jsonpath='{range .subsets[*].addresses[*]}{.ip}{"\n"}{end}' 2>/dev/null | grep -c '[0-9]' || true)
  if [ "${EP:-0}" -ge 2 ] 2>/dev/null; then break; fi
  sleep 2
done
if [ "${EP:-0}" -ge 2 ] 2>/dev/null; then
  ok "the Service has endpoints ($EP endpoint addresses)"
else
  bad "the Service has endpoints (got $EP, want at least 2)"
fi

READY=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
eq "the Deployment has 2 ready replicas" "$READY" "2"

# ---- live check: does the Service really serve the pods? ----
k -n "$NS" delete pod "$LIVE" --ignore-not-found --wait=false >/dev/null 2>&1

cat <<EOF | k apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: $LIVE
  namespace: $NS
  labels:
    cka-lab: live-check
spec:
  restartPolicy: Never
  containers:
    - name: probe
      image: busybox:1.36
      command:
        - sh
        - -c
        - "wget -q -T 5 -O - http://$SVC.$NS.svc.cluster.local:80/ >/dev/null && echo SERVICE_OK || echo SERVICE_FAILED"
EOF

LIVEPHASE=""
for i in $(seq 1 30); do
  LIVEPHASE=$(k -n "$NS" get pod "$LIVE" -o jsonpath='{.status.phase}' 2>/dev/null)
  case "$LIVEPHASE" in
    Succeeded|Failed) break ;;
  esac
  sleep 2
done

LIVELOG=$(k -n "$NS" logs "$LIVE" 2>/dev/null)
case "$LIVELOG" in
  *SERVICE_OK*)
    ok "a pod inside the cluster can fetch the Service and gets the page back" ;;
  *SERVICE_FAILED*)
    bad "a pod inside the cluster can fetch the Service and gets the page back (the request failed)" ;;
  *)
    skip "the live check could not be run in this environment (pod phase '${LIVEPHASE:-?}')" ;;
esac

k -n "$NS" delete pod "$LIVE" --ignore-not-found --wait=false >/dev/null 2>&1

note "A readiness probe is what the endpoints controller keys off: a pod that"
note "is not Ready is taken out of the Endpoints and stops receiving traffic."
note "A NodePort is published on the node's IP, so it is reachable from"
note "outside the cluster - a ClusterIP is not."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}w19 PASSED${X}"; else echo -e "${R}w19 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
