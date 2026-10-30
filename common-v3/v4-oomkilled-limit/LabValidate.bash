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

NS=oom
DEP=greedy

echo "== v4: The pod that keeps being killed =="

if ! exists "Deployment $DEP exists in namespace $NS" -n "$NS" deploy "$DEP"; then
  echo; echo -e "${R}v4 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the container must still have a limit ----
LIM=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}' 2>/dev/null)
REQ=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}' 2>/dev/null)
nonempty "the container still has a memory limit" "$LIM"
nonempty "the container still has a memory request" "$REQ"

# limit >= request, in MiB
to_mib(){ printf '%s' "$1" | awk '{ s=$0; if (s ~ /Mi$/) { sub(/Mi$/,"",s); v=s } else if (s ~ /Gi$/) { sub(/Gi$/,"",s); v=s*1024 } else if (s ~ /Ki$/) { sub(/Ki$/,"",s); v=s/1024 } else { v=s/1048576 } printf "%d", v }'; }
LM=$(to_mib "$LIM"); RM=$(to_mib "$REQ")
if [ -n "$LM" ] && [ -n "$RM" ] && [ "$LM" -ge "$RM" ] 2>/dev/null; then
  ok "the memory limit ($LIM) is at least the request ($REQ)"
else
  bad "the memory limit is at least the request (limit '$LIM', request '$REQ')"
fi

# ---- the pod ----
POD=$(k -n "$NS" get pods -l "app=$DEP" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$POD" ]; then
  bad "a pod exists for the $DEP deployment"
  echo; echo -e "${R}v4 FAILED ($FAILS checks)${X}"; exit 1
fi
ok "the pod is $POD"

PHASE=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null)
eq "the pod is Running" "$PHASE" "Running"

READY=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
eq "the container is ready" "$READY" "true"

# ---- it is not being OOMKilled any more ----
LASTREASON=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}' 2>/dev/null)
if [ "$LASTREASON" = "OOMKilled" ]; then
  bad "the container is no longer being OOMKilled (its last termination was still OOMKilled)"
else
  ok "the container is no longer being OOMKilled (last termination: ${LASTREASON:-<none>})"
fi

# ---- and the restart count has stopped climbing ----
R1=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
echo "Sampling the restart count twice, ten seconds apart..."
sleep 10
R2=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
if [ -n "$R1" ] && [ "$R1" = "$R2" ]; then
  ok "the restart count has stopped climbing (it stayed at $R1)"
else
  bad "the restart count has stopped climbing (it went from '$R1' to '$R2')"
fi

note "OOMKilled is the kubelet's way of saying the cgroup ran out of memory."
note "The pod's phase and the restart count tell you it is looping; the container's"
note "lastState.terminated.reason tells you WHY."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}v4 PASSED${X}"; else echo -e "${R}v4 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
