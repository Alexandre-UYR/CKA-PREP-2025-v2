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

NS=default
DEP=wordpress

# "2"  -> 2000 millicores,  "3900m" -> 3900 millicores
to_mcpu(){ printf '%s' "$1" | awk '{ if ($0 ~ /m$/) printf "%d", substr($0,1,length($0)-1); else printf "%d", $0*1000 }'; }
# "600Mi" -> 600, "1Gi" -> 1024, "1048576" (bytes) -> 1, "1G" -> 953
to_mib(){ printf '%s' "$1" | awk '
  { s=$0; u="B";
    if (s ~ /Ki$/) { u="Ki"; s=substr(s,1,length(s)-2) }
    else if (s ~ /Mi$/) { u="Mi"; s=substr(s,1,length(s)-2) }
    else if (s ~ /Gi$/) { u="Gi"; s=substr(s,1,length(s)-2) }
    else if (s ~ /Ti$/) { u="Ti"; s=substr(s,1,length(s)-2) }
    else if (s ~ /K$/) { u="K"; s=substr(s,1,length(s)-1) }
    else if (s ~ /M$/) { u="M"; s=substr(s,1,length(s)-1) }
    else if (s ~ /G$/) { u="G"; s=substr(s,1,length(s)-1) }
    else if (s ~ /T$/) { u="T"; s=substr(s,1,length(s)-1) }
    v = s + 0;
    if (u=="Ki") v = v/1024;
    else if (u=="Mi") v = v;
    else if (u=="Gi") v = v*1024;
    else if (u=="Ti") v = v*1048576;
    else if (u=="B")  v = v/1048576;
    else if (u=="K")  v = v*1000/1048576;
    else if (u=="M")  v = v*1000000/1048576;
    else if (u=="G")  v = v*1000000000/1048576;
    else if (u=="T")  v = v*1000000000000/1048576;
    printf "%d", v }'; }

echo "== Q4: resource allocation =="

# --- The node whose resources are being divided ---------------------------
NODE="$(k get pods -n "$NS" -l app=wordpress -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)"
if [ -z "$NODE" ]; then
  NODE="$(k get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
fi
if [ -n "$NODE" ]; then
  ok "Node under test: $NODE"
else
  bad "Node under test: no node could be found"
fi

ALLOC_CPU_RAW="$(k get node "$NODE" -o jsonpath='{.status.allocatable.cpu}' 2>/dev/null)"
ALLOC_MEM_RAW="$(k get node "$NODE" -o jsonpath='{.status.allocatable.memory}' 2>/dev/null)"
ALLOC_CPU="$(to_mcpu "$ALLOC_CPU_RAW")"
ALLOC_MEM="$(to_mib "$ALLOC_MEM_RAW")"
if [ -n "$ALLOC_CPU" ] && [ "${ALLOC_CPU:-0}" -gt 0 ] 2>/dev/null; then
  ok "Node allocatable: ${ALLOC_CPU_RAW} CPU, ${ALLOC_MEM_RAW} memory (${ALLOC_CPU}m, ${ALLOC_MEM}Mi)"
else
  bad "Node allocatable could not be read from node '$NODE' (got cpu='$ALLOC_CPU_RAW', memory='$ALLOC_MEM_RAW')"
fi

# --- The deployment the candidate had to re-size --------------------------
exists "Deployment $DEP exists in namespace $NS" deploy "$DEP" -n "$NS"
REP="$(k get deploy "$DEP" -n "$NS" -o jsonpath='{.spec.replicas}' 2>/dev/null)"
eq "Deployment $DEP is scaled back to 3 replicas" "$REP" "3"
READY="$(k get deploy "$DEP" -n "$NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"
eq "Deployment $DEP has 3 ready replicas" "$READY" "3"

getf(){ k get deploy "$DEP" -n "$NS" -o jsonpath="$1" 2>/dev/null; }

C_NAMES="$(getf '{.spec.template.spec.containers[*].name}')"
I_NAMES="$(getf '{.spec.template.spec.initContainers[*].name}')"

# --- Every container has to declare requests AND limits -------------------
# The pod-level request is max(sum of the app containers, max of the init
# containers): init containers run one after another, app containers in parallel.
POD_REQ_CPU=0
POD_REQ_MEM=0
MAX_INIT_CPU=0
MAX_INIT_MEM=0

i=0
for n in $C_NAMES; do
  rc="$(getf "{.spec.template.spec.containers[$i].resources.requests.cpu}")"
  rm_="$(getf "{.spec.template.spec.containers[$i].resources.requests.memory}")"
  lc="$(getf "{.spec.template.spec.containers[$i].resources.limits.cpu}")"
  lm="$(getf "{.spec.template.spec.containers[$i].resources.limits.memory}")"
  nonempty "Container '$n' sets resources.requests.cpu" "$rc"
  nonempty "Container '$n' sets resources.requests.memory" "$rm_"
  nonempty "Container '$n' sets resources.limits.cpu" "$lc"
  nonempty "Container '$n' sets resources.limits.memory" "$lm"
  if [ -n "$rc" ] && [ -n "$lc" ]; then
    rc_m="$(to_mcpu "$rc")"; lc_m="$(to_mcpu "$lc")"
    if [ "${lc_m:-0}" -ge "${rc_m:-0}" ]; then
      ok "Container '$n' limits.cpu ($lc) is >= requests.cpu ($rc)"
    else
      bad "Container '$n' limits.cpu ($lc) is >= requests.cpu ($rc)"
    fi
    POD_REQ_CPU=$(( POD_REQ_CPU + rc_m ))
  fi
  if [ -n "$rm_" ] && [ -n "$lm" ]; then
    rm_m="$(to_mib "$rm_")"; lm_m="$(to_mib "$lm")"
    if [ "${lm_m:-0}" -ge "${rm_m:-0}" ]; then
      ok "Container '$n' limits.memory ($lm) is >= requests.memory ($rm_)"
    else
      bad "Container '$n' limits.memory ($lm) is >= requests.memory ($rm_)"
    fi
    POD_REQ_MEM=$(( POD_REQ_MEM + rm_m ))
  fi
  i=$(( i + 1 ))
done

i=0
for n in $I_NAMES; do
  rc="$(getf "{.spec.template.spec.initContainers[$i].resources.requests.cpu}")"
  rm_="$(getf "{.spec.template.spec.initContainers[$i].resources.requests.memory}")"
  lc="$(getf "{.spec.template.spec.initContainers[$i].resources.limits.cpu}")"
  lm="$(getf "{.spec.template.spec.initContainers[$i].resources.limits.memory}")"
  nonempty "Init container '$n' sets resources.requests.cpu" "$rc"
  nonempty "Init container '$n' sets resources.requests.memory" "$rm_"
  nonempty "Init container '$n' sets resources.limits.cpu" "$lc"
  nonempty "Init container '$n' sets resources.limits.memory" "$lm"
  if [ -n "$rc" ] && [ -n "$lc" ]; then
    rc_m="$(to_mcpu "$rc")"; lc_m="$(to_mcpu "$lc")"
    if [ "${lc_m:-0}" -ge "${rc_m:-0}" ]; then
      ok "Init container '$n' limits.cpu ($lc) is >= requests.cpu ($rc)"
    else
      bad "Init container '$n' limits.cpu ($lc) is >= requests.cpu ($rc)"
    fi
    if [ "${rc_m:-0}" -gt "${MAX_INIT_CPU}" ]; then MAX_INIT_CPU="${rc_m:-0}"; fi
  fi
  if [ -n "$rm_" ] && [ -n "$lm" ]; then
    rm_m="$(to_mib "$rm_")"; lm_m="$(to_mib "$lm")"
    if [ "${lm_m:-0}" -ge "${rm_m:-0}" ]; then
      ok "Init container '$n' limits.memory ($lm) is >= requests.memory ($rm_)"
    else
      bad "Init container '$n' limits.memory ($lm) is >= requests.memory ($rm_)"
    fi
    if [ "${rm_m:-0}" -gt "${MAX_INIT_MEM}" ]; then MAX_INIT_MEM="${rm_m:-0}"; fi
  fi
  i=$(( i + 1 ))
done

# --- The init container and the main container must be identical ----------
APP_REQ_CPU="$(getf '{.spec.template.spec.containers[0].resources.requests.cpu}')"
APP_REQ_MEM="$(getf '{.spec.template.spec.containers[0].resources.requests.memory}')"
APP_LIM_CPU="$(getf '{.spec.template.spec.containers[0].resources.limits.cpu}')"
APP_LIM_MEM="$(getf '{.spec.template.spec.containers[0].resources.limits.memory}')"
INIT_REQ_CPU="$(getf '{.spec.template.spec.initContainers[0].resources.requests.cpu}')"
INIT_REQ_MEM="$(getf '{.spec.template.spec.initContainers[0].resources.requests.memory}')"
INIT_LIM_CPU="$(getf '{.spec.template.spec.initContainers[0].resources.limits.cpu}')"
INIT_LIM_MEM="$(getf '{.spec.template.spec.initContainers[0].resources.limits.memory}')"

if [ -n "$INIT_REQ_CPU" ] && [ -n "$APP_REQ_CPU" ]; then
  eq "Init container and main container have the same requests.cpu" "$(to_mcpu "$INIT_REQ_CPU")" "$(to_mcpu "$APP_REQ_CPU")"
else
  bad "Init container and main container have the same requests.cpu (init='$INIT_REQ_CPU', main='$APP_REQ_CPU')"
fi
if [ -n "$INIT_REQ_MEM" ] && [ -n "$APP_REQ_MEM" ]; then
  eq "Init container and main container have the same requests.memory" "$(to_mib "$INIT_REQ_MEM")" "$(to_mib "$APP_REQ_MEM")"
else
  bad "Init container and main container have the same requests.memory (init='$INIT_REQ_MEM', main='$APP_REQ_MEM')"
fi
if [ -n "$INIT_LIM_CPU" ] && [ -n "$APP_LIM_CPU" ]; then
  eq "Init container and main container have the same limits.cpu" "$(to_mcpu "$INIT_LIM_CPU")" "$(to_mcpu "$APP_LIM_CPU")"
else
  bad "Init container and main container have the same limits.cpu (init='$INIT_LIM_CPU', main='$APP_LIM_CPU')"
fi
if [ -n "$INIT_LIM_MEM" ] && [ -n "$APP_LIM_MEM" ]; then
  eq "Init container and main container have the same limits.memory" "$(to_mib "$INIT_LIM_MEM")" "$(to_mib "$APP_LIM_MEM")"
else
  bad "Init container and main container have the same limits.memory (init='$INIT_LIM_MEM', main='$APP_LIM_MEM')"
fi

# --- Fair share of the node ------------------------------------------------
EFF_CPU="$POD_REQ_CPU"
if [ "${MAX_INIT_CPU:-0}" -gt "${EFF_CPU:-0}" ]; then EFF_CPU="${MAX_INIT_CPU:-0}"; fi
EFF_MEM="$POD_REQ_MEM"
if [ "${MAX_INIT_MEM:-0}" -gt "${EFF_MEM:-0}" ]; then EFF_MEM="${MAX_INIT_MEM:-0}"; fi

if [ -n "$ALLOC_CPU" ] && [ "${ALLOC_CPU:-0}" -gt 0 ] 2>/dev/null; then
  TOTAL_CPU=$(( EFF_CPU * 3 ))
  SHARE_CPU=$(( ALLOC_CPU / 3 ))
  HALF_CPU=$(( ALLOC_CPU / 2 ))
  if [ "${TOTAL_CPU:-0}" -le "${ALLOC_CPU:-0}" ]; then
    ok "3 pods requesting ${EFF_CPU}m CPU each stay inside the node's ${ALLOC_CPU}m allocatable (total ${TOTAL_CPU}m, fair share ${SHARE_CPU}m per pod)"
  else
    bad "3 pods requesting ${EFF_CPU}m CPU each stay inside the node's ${ALLOC_CPU}m allocatable (total ${TOTAL_CPU}m > ${ALLOC_CPU}m, fair share is ${SHARE_CPU}m per pod)"
  fi
  if [ "${TOTAL_CPU:-0}" -ge "${HALF_CPU:-0}" ]; then
    ok "The CPU given out is a fair share of the node (3 x ${EFF_CPU}m = ${TOTAL_CPU}m, at least half of ${ALLOC_CPU}m, fair share ${SHARE_CPU}m per pod)"
  else
    bad "The CPU given out is a fair share of the node (3 x ${EFF_CPU}m = ${TOTAL_CPU}m is less than half of ${ALLOC_CPU}m, fair share is ${SHARE_CPU}m per pod)"
  fi
else
  bad "The CPU given out is a fair share of the node (the node's allocatable CPU could not be read)"
fi

if [ -n "$ALLOC_MEM" ] && [ "${ALLOC_MEM:-0}" -gt 0 ] 2>/dev/null; then
  TOTAL_MEM=$(( EFF_MEM * 3 ))
  SHARE_MEM=$(( ALLOC_MEM / 3 ))
  HALF_MEM=$(( ALLOC_MEM / 2 ))
  if [ "${TOTAL_MEM:-0}" -le "${ALLOC_MEM:-0}" ]; then
    ok "3 pods requesting ${EFF_MEM}Mi memory each stay inside the node's ${ALLOC_MEM}Mi allocatable (total ${TOTAL_MEM}Mi, fair share ${SHARE_MEM}Mi per pod)"
  else
    bad "3 pods requesting ${EFF_MEM}Mi memory each stay inside the node's ${ALLOC_MEM}Mi allocatable (total ${TOTAL_MEM}Mi > ${ALLOC_MEM}Mi, fair share is ${SHARE_MEM}Mi per pod)"
  fi
  if [ "${TOTAL_MEM:-0}" -ge "${HALF_MEM:-0}" ]; then
    ok "The memory given out is a fair share of the node (3 x ${EFF_MEM}Mi = ${TOTAL_MEM}Mi, at least half of ${ALLOC_MEM}Mi, fair share ${SHARE_MEM}Mi per pod)"
  else
    bad "The memory given out is a fair share of the node (3 x ${EFF_MEM}Mi = ${TOTAL_MEM}Mi is less than half of ${ALLOC_MEM}Mi, fair share is ${SHARE_MEM}Mi per pod)"
  fi
else
  bad "The memory given out is a fair share of the node (the node's allocatable memory could not be read)"
fi

if [ "$FAILS" -eq 0 ]; then echo -e "${G}Q4 PASSED${X}"; else echo -e "${R}Q4 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
