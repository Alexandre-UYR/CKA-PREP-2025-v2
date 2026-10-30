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

NS=quota
QUOTA=compute-quota
DEP=app

echo "== v16: The API server that says no =="

# ---- the quota is pre-state and has to still be there ----
if ! exists "ResourceQuota $QUOTA exists in namespace $NS" -n "$NS" resourcequota "$QUOTA"; then
  echo; echo -e "${R}v16 FAILED ($FAILS checks)${X}"; exit 1
fi

quota_hard(){
  local v
  v=$(k -n "$NS" get resourcequota "$QUOTA" -o jsonpath="{.status.hard.$1}" 2>/dev/null | tr -d '[:space:]')
  [ -z "$v" ] && v=$(k -n "$NS" get resourcequota "$QUOTA" -o jsonpath="{.spec.hard.$1}" 2>/dev/null | tr -d '[:space:]')
  printf '%s' "$v"
}

HC=$(quota_hard 'requests\.cpu')
HM=$(quota_hard 'requests\.memory')
LC=$(quota_hard 'limits\.cpu')
LM=$(quota_hard 'limits\.memory')

MISSING=""
[ -z "$HC" ] && MISSING="$MISSING requests.cpu"
[ -z "$HM" ] && MISSING="$MISSING requests.memory"
[ -z "$LC" ] && MISSING="$MISSING limits.cpu"
[ -z "$LM" ] && MISSING="$MISSING limits.memory"
if [ -z "$MISSING" ]; then
  ok "the quota still requires requests.cpu, requests.memory, limits.cpu and limits.memory"
else
  bad "the quota still requires all four resources (missing:$MISSING)"
fi

if [ "$(to_milli "$HC")" = "2000" ] && [ "$(to_mib "$HM")" = "4096" ] \
   && [ "$(to_milli "$LC")" = "2000" ] && [ "$(to_mib "$LM")" = "4096" ]; then
  ok "the quota's hard limits were not raised ($HC cpu, $HM memory)"
else
  bad "the quota's hard limits were not raised (got requests.cpu '$HC', requests.memory '$HM', limits.cpu '$LC', limits.memory '$LM')"
fi

# ---- the Deployment itself ----
if ! exists "Deployment $DEP exists in namespace $NS" -n "$NS" deploy "$DEP"; then
  echo; echo -e "${R}v16 FAILED ($FAILS checks)${X}"; exit 1
fi

# Give the workload a moment to settle before judging it, so that a manifest
# applied a second ago is not failed for not having rolled out yet.
echo "Waiting for the workload to come up..."
i=0
while [ "$i" -lt 30 ]; do
  READYREP=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [ "$READYREP" = "1" ] && break
  sleep 2
  i=$((i+2))
done

# ---- the resources on the container ----
# Prints the resource fields that are not set, as "container:field".
resources_missing(){
  local kind=$1 name=$2 base i c v miss="" pair label path
  if [ "$kind" = "deploy" ]; then base=".spec.template.spec.containers"; else base=".spec.containers"; fi
  i=0
  while [ "$i" -lt 10 ]; do
    c=$(k -n "$NS" get "$kind" "$name" -o jsonpath="{$base[$i].name}" 2>/dev/null)
    [ -z "$c" ] && break
    for pair in 'requests.cpu|requests.cpu' 'requests.memory|requests.memory' \
                'limits.cpu|limits.cpu' 'limits.memory|limits.memory'; do
      label=${pair%%|*}
      path=${pair##*|}
      v=$(k -n "$NS" get "$kind" "$name" -o jsonpath="{$base[$i].resources.$path}" 2>/dev/null)
      [ -z "$v" ] && miss="$miss $c:$label"
    done
    i=$((i+1))
  done
  printf '%s' "$miss"
}

DEP_MISSING=$(resources_missing deploy "$DEP")
POD=$(k -n "$NS" get pods -l "app=$DEP" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
POD_MISSING=""
[ -n "$POD" ] && POD_MISSING=$(resources_missing pod "$POD")

if [ -z "$DEP_MISSING" ]; then
  ok "the container declares requests.cpu, requests.memory, limits.cpu and limits.memory"
elif [ -n "$POD" ] && [ -z "$POD_MISSING" ]; then
  ok "the container declares requests.cpu, requests.memory, limits.cpu and limits.memory (the LimitRange supplied them)"
  note "the Deployment's pod template leaves them out; the LimitRange applied the"
  note "defaults when the Pod was admitted, and the quota saw the defaulted values."
else
  bad "the container declares requests.cpu, requests.memory, limits.cpu and limits.memory (missing in the Deployment:${DEP_MISSING:- none}, missing in the Pod:${POD_MISSING:- none})"
fi

# ---- the requests have to fit inside the quota ----
SUM_CPU=0
SUM_MEM=0
i=0
while [ "$i" -lt 10 ]; do
  if [ -n "$POD" ]; then
    c=$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.containers[$i].name}" 2>/dev/null)
    rc=$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.containers[$i].resources.requests.cpu}" 2>/dev/null)
    rm=$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.containers[$i].resources.requests.memory}" 2>/dev/null)
  else
    c=$(k -n "$NS" get deploy "$DEP" -o jsonpath="{.spec.template.spec.containers[$i].name}" 2>/dev/null)
    rc=$(k -n "$NS" get deploy "$DEP" -o jsonpath="{.spec.template.spec.containers[$i].resources.requests.cpu}" 2>/dev/null)
    rm=$(k -n "$NS" get deploy "$DEP" -o jsonpath="{.spec.template.spec.containers[$i].resources.requests.memory}" 2>/dev/null)
  fi
  [ -z "$c" ] && break
  SUM_CPU=$((SUM_CPU + $(to_milli "$rc")))
  SUM_MEM=$((SUM_MEM + $(to_mib "$rm")))
  i=$((i+1))
done

if [ -n "$HC" ] && [ -n "$HM" ]; then
  if [ "$SUM_CPU" -le "$(to_milli "$HC")" ] && [ "$SUM_MEM" -le "$(to_mib "$HM")" ]; then
    ok "the requests fit inside the quota (cpu $(to_milli "$HC") milli, memory $(to_mib "$HM") MiB available)"
  else
    bad "the requests fit inside the quota (using cpu $SUM_CPU milli and memory $SUM_MEM MiB, allowed cpu $(to_milli "$HC") milli, memory $(to_mib "$HM") MiB)"
  fi
else
  bad "the requests fit inside the quota (the quota's hard limits could not be read)"
fi

# ---- and it has to run ----
READYREP=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
eq "the Deployment has 1 ready replica" "$READYREP" "1"

if [ -z "$POD" ]; then
  bad "a pod exists for the $DEP deployment"
  echo; echo -e "${R}v16 FAILED ($FAILS checks)${X}"; exit 1
fi
ok "the pod is $POD"

PHASE=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null)
eq "the pod is Running" "$PHASE" "Running"

READY_NAMES=$(k -n "$NS" get pod "$POD" \
              -o jsonpath='{range .status.containerStatuses[*]}{.name}={.ready}{"\n"}{end}' 2>/dev/null \
              | grep '=true$' | tr -d '\r')
READY_COUNT=$(printf '%s\n' "$READY_NAMES" | grep -c '[^[:space:]]')
eq "the pod has 1 ready container" "$READY_COUNT" "1"

note "A ResourceQuota is enforced at admission time by the API server, not by a"
note "controller: the object is refused, so nothing is created and there is no"
note "object to look at afterwards - only the error, which names the quota and"
note "the fields that are missing."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}v16 PASSED${X}"; else echo -e "${R}v16 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
