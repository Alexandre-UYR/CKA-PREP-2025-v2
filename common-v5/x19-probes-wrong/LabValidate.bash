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

NS=probe
DEP=probed
LABDIR=/tmp/cka-lab

echo "== x19: Two probes, both wrong =="

if ! exists "Deployment $DEP exists in namespace $NS" -n "$NS" deploy "$DEP"; then
  echo; echo -e "${R}x19 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- it was edited in place, not deleted and re-created ----
ORIG=$(cat "$LABDIR/x19.dep.uid" 2>/dev/null || true)
NOW=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.metadata.uid}' 2>/dev/null)
if [ -z "$ORIG" ]; then
  bad "the Deployment was fixed in place, not re-created (no UID was recorded at setup)"
elif [ "$ORIG" = "$NOW" ]; then
  ok "the Deployment was fixed in place, not re-created (its UID is unchanged)"
else
  bad "the Deployment was fixed in place, not re-created (its UID changed)"
fi

# ---- wait for the rollout, then look at the pods ----
READYREP=""
i=0
while [ "$i" -lt 150 ]; do
  READYREP=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null) || READYREP=""
  PODS=$(k -n "$NS" get pods -l "app=$DEP" \
           -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)
  NPODS=$(printf '%s\n' "$PODS" | grep -c . || true)
  CLEAN=1
  for P in $PODS; do
    PH=$(k -n "$NS" get pod "$P" -o jsonpath='{.status.phase}' 2>/dev/null)
    RC=$(k -n "$NS" get pod "$P" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
    RD=$(k -n "$NS" get pod "$P" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [ "$PH" != "Running" ] || [ "${RC:-0}" != "0" ] || [ "$RD" != "True" ]; then CLEAN=0; fi
  done
  if [ "${READYREP:-0}" -ge 2 ] 2>/dev/null && [ "${NPODS:-0}" -eq 2 ] 2>/dev/null && [ "$CLEAN" = "1" ]; then break; fi
  sleep 3
  i=$((i+3))
done

eq "the Deployment has 2 ready replicas" "${READYREP:-}" "2"

# ---- the pods themselves ----
PODS=$(k -n "$NS" get pods -l "app=$DEP" \
         -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)
NPODS=$(printf '%s\n' "$PODS" | grep -c . || true)
eq "the Deployment has 2 pods" "${NPODS:-0}" "2"

BADPHASE=""
BADRESTART=""
NOTREADY=""
for P in $PODS; do
  PH=$(k -n "$NS" get pod "$P" -o jsonpath='{.status.phase}' 2>/dev/null)
  RC=$(k -n "$NS" get pod "$P" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
  RD=$(k -n "$NS" get pod "$P" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  [ "$PH" = "Running" ] || BADPHASE="$BADPHASE $P($PH)"
  [ "${RC:-0}" = "0" ] || BADRESTART="$BADRESTART $P($RC)"
  [ "$RD" = "True" ] || NOTREADY="$NOTREADY $P(${RD:-?})"
done

if [ -z "$BADPHASE" ]; then
  ok "every pod is Running"
else
  bad "every pod is Running (not Running:${BADPHASE})"
fi
if [ -z "$BADRESTART" ]; then
  ok "no container has been restarted (restartCount 0)"
else
  bad "no container has been restarted (restartCount not 0:${BADRESTART})"
fi
if [ -z "$NOTREADY" ]; then
  ok "every pod is Ready"
else
  bad "every pod is Ready (Ready condition not True:${NOTREADY})"
fi

# ---- the liveness probe ----
# A liveness probe that points at nothing is what produces a restart count
# and eventually a killed container. It has to be gone, or it has to point at
# something that answers.
LHAS=$(k -n "$NS" get deploy "$DEP" -o go-template='{{if .spec.template.spec.containers[0].livenessProbe}}yes{{end}}' 2>/dev/null)
LPATH=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.httpGet.path}' 2>/dev/null)
LPORT=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.httpGet.port}' 2>/dev/null)
LTCP=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.tcpSocket.port}' 2>/dev/null)
LEXEC=$(k -n "$NS" get deploy "$DEP" -o go-template='{{range $i, $c := .spec.template.spec.containers[0].livenessProbe.exec.command}}{{if $i}} {{end}}{{printf "%q" $c}}{{end}}' 2>/dev/null)

POD1=$(printf '%s\n' "$PODS" | grep . | head -n 1)

# Ask the pod's own server whether the probe's target answers. The pod proxy
# goes through the API server to the kubelet and the container, so a 2xx here
# is the same answer the kubelet gets.
proxy_try(){
  k get --raw "/api/v1/namespaces/$NS/pods/$1:$2/proxy$3" >/dev/null 2>&1 && return 0
  k get --raw "/api/v1/namespaces/$NS/pods/http:$1:$2/proxy$3" >/dev/null 2>&1 && return 0
  return 1
}
resolve_port(){
  local p=$1
  case "$p" in
    ''|*[!0-9]*) ;;
    *) echo "$p"; return;;
  esac
  k -n "$NS" get deploy "$DEP" -o go-template="{{range .spec.template.spec.containers[0].ports}}{{if eq .name \"$p\"}}{{.containerPort}}{{end}}{{end}}" 2>/dev/null
}

if [ -z "$LHAS" ]; then
  ok "the liveness probe has been removed, so there is nothing left to kill the container"
elif [ -n "$LEXEC" ]; then
  if [ -z "$POD1" ]; then
    bad "the liveness probe is an exec probe that succeeds (there is no pod to run it in)"
  elif eval "k -n '$NS' exec '$POD1' -- $LEXEC" >/dev/null 2>&1; then
    ok "the liveness probe is an exec probe and it succeeds inside the container"
  else
    bad "the liveness probe is an exec probe but it fails inside the container"
  fi
else
  PORTNUM=$(resolve_port "$LPORT")
  if [ -z "$PORTNUM" ] && [ -n "$LTCP" ]; then PORTNUM=$(resolve_port "$LTCP"); fi
  if [ -z "$PORTNUM" ]; then
    bad "the liveness probe points at a port the container does not declare (got '${LPORT}${LTCP}', which resolves to nothing)"
  elif [ -z "$POD1" ]; then
    bad "the liveness probe points at something that answers (there is no pod to ask)"
  elif proxy_try "$POD1" 80 "/"; then
    # The proxy works, so its answer is trustworthy.
    if [ -n "$LTCP" ]; then
      if proxy_try "$POD1" "$PORTNUM" "/"; then
        ok "the liveness probe is a tcpSocket probe on port $PORTNUM, and that port answers"
      else
        bad "the liveness probe is a tcpSocket probe on port $PORTNUM, but that port does not answer"
      fi
    elif proxy_try "$POD1" "$PORTNUM" "$LPATH"; then
      ok "the liveness probe points at port $PORTNUM path ${LPATH:-/}, and the server answers it"
    else
      bad "the liveness probe points at port $PORTNUM path ${LPATH:-/}, and the server does not answer it"
    fi
  else
    # The pod proxy is not usable here, so fall back to what the server is
    # known to serve. This server answers / and nothing else.
    note "the pod proxy is not available, so the liveness probe is checked against the server's known paths"
    if [ -n "$LTCP" ]; then
      if [ "$PORTNUM" = "80" ]; then
        ok "the liveness probe is a tcpSocket probe on port 80, where the server listens"
      else
        bad "the liveness probe is a tcpSocket probe on port $PORTNUM, and nothing listens there"
      fi
    elif [ "$PORTNUM" = "80" ] && { [ -z "$LPATH" ] || [ "$LPATH" = "/" ]; }; then
      ok "the liveness probe points at path ${LPATH:-/} on port 80, which the server serves"
    else
      bad "the liveness probe points at port $PORTNUM path ${LPATH:-/}, and the server does not serve that"
    fi
  fi
fi

note "A readiness probe decides whether a pod receives traffic through a"
note "Service. A liveness probe decides whether the kubelet kills the"
note "container - and it will, once the budget of periodSeconds x"
note "failureThreshold has passed."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}x19 PASSED${X}"; else echo -e "${R}x19 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
