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

NS=svctypes
DEP=web

# How many endpoint addresses does a Service have?
# The Endpoints API is the classic answer; EndpointSlice is the fallback, for
# clusters where the Endpoints resource is gone or trimmed down.
ep_count(){
  local ns=$1 svc=$2 n
  n=$(k -n "$ns" get endpoints "$svc" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null \
      | tr -s ' ' '\n' | grep -c '[^[:space:]]')
  if [ "${n:-0}" -gt 0 ]; then
    printf '%s' "$n"
    return
  fi
  n=$(k -n "$ns" get endpointslice -l "kubernetes.io/service-name=$svc" \
      -o jsonpath='{.items[*].endpoints[*].addresses[*]}' 2>/dev/null \
      | tr -s ' ' '\n' | grep -c '[^[:space:]]')
  printf '%s' "${n:-0}"
}

echo "== c15: The three Service types =="

if ! exists "Deployment $DEP exists in namespace $NS" -n "$NS" deploy "$DEP"; then
  echo; echo -e "${R}c15 FAILED ($FAILS checks)${X}"; exit 1
fi

# The pods have to be up before endpoints can exist.
i=0
READY=""
while [ $i -lt 30 ]; do
  READY=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  case "$READY" in ''|*[!0-9]*) READY=0;; esac
  [ "$READY" -ge 1 ] && break
  i=$((i+1)); sleep 3
done
if [ "${READY:-0}" -ge 1 ]; then
  ok "the Deployment $DEP has at least 1 ready replica"
else
  bad "the Deployment $DEP has at least 1 ready replica (the pre-state is not up - this is not the candidate's answer)"
fi

for pair in "web-clusterip:ClusterIP" "web-nodeport:NodePort" "web-loadbalancer:LoadBalancer"; do
  SVC="${pair%%:*}"
  WANT="${pair##*:}"
  echo
  echo "-- Service $SVC --"

  if ! exists "Service $SVC exists in namespace $NS" -n "$NS" svc "$SVC"; then
    continue
  fi

  STYPE=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.type}' 2>/dev/null)
  eq "the $SVC type is $WANT" "$STYPE" "$WANT"

  PORT=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.ports[*].port}' 2>/dev/null)
  case " $PORT " in
    *" 80 "*) ok "the $SVC port is 80";;
    *) bad "the $SVC port is 80 (got '$PORT')";;
  esac

  TPORT=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.ports[*].targetPort}' 2>/dev/null)
  case " $TPORT " in
    *" 80 "*) ok "the $SVC targetPort is 80";;
    *) bad "the $SVC targetPort is 80 (got '$TPORT')";;
  esac

  N=$(ep_count "$NS" "$SVC")
  if [ "${N:-0}" -gt 0 ]; then
    ok "the $SVC has at least one endpoint address"
  else
    bad "the $SVC has at least one endpoint address (got none - a Service only gets endpoints if its selector matches the pods)"
  fi
done

echo
echo "-- the NodePort --"

NP=$(k -n "$NS" get svc web-nodeport -o jsonpath='{.spec.ports[*].nodePort}' 2>/dev/null)
eq "the web-nodeport nodePort is 30080" "$NP" "30080"

note "A ClusterIP Service is only reachable inside the cluster. A NodePort is"
note "published on every node on the port in the cluster's node port range."
note "A LoadBalancer asks the cloud provider for an external IP."
note "On a cluster with no load balancer implementation (kind, plain minikube)"
note "the LoadBalancer Service stays <pending> with no external IP - that is an"
note "environment limitation, not a wrong answer, so it is not graded here."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c15 PASSED${X}"; else echo -e "${R}c15 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
