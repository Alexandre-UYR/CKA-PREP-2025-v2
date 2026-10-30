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

NS=qos
DEP=mixed

echo "== v20: Guaranteed, not Burstable =="

# ---------------------------------------------------------------------------
# quantity helpers - CPU in millicores, memory in bytes, so that "200m" and
# "0.2" compare as the same value and "256Mi" compares as the same size
# whatever suffix the candidate typed.
# ---------------------------------------------------------------------------
to_mc(){
  printf '%s' "$1" | LC_ALL=C awk '
  { s=$0; gsub(/[[:space:]]/,"",s);
    if (s ~ /m$/) { sub(/m$/,"",s); v=s+0 }
    else if (s ~ /^[0-9]+(\.[0-9]+)?$/) { v=(s+0)*1000 }
    else { v=0 }
    printf "%.0f", v }'
}

to_bytes(){
  printf '%s' "$1" | LC_ALL=C awk '
  { s=$0; gsub(/[[:space:]]/,"",s);
    if      (s ~ /Ei$/) { sub(/Ei$/,"",s); v=(s+0)*1024*1024*1024*1024 }
    else if (s ~ /Pi$/) { sub(/Pi$/,"",s); v=(s+0)*1024*1024*1024*1024*1024 }
    else if (s ~ /Ti$/) { sub(/Ti$/,"",s); v=(s+0)*1024*1024*1024 }
    else if (s ~ /Gi$/) { sub(/Gi$/,"",s); v=(s+0)*1024*1024*1024 }
    else if (s ~ /Mi$/) { sub(/Mi$/,"",s); v=(s+0)*1024*1024 }
    else if (s ~ /Ki$/) { sub(/Ki$/,"",s); v=(s+0)*1024 }
    else if (s ~ /E$/)  { sub(/E$/,"",s);  v=(s+0)*1000000000000000000 }
    else if (s ~ /P$/)  { sub(/P$/,"",s);  v=(s+0)*1000000000000000 }
    else if (s ~ /T$/)  { sub(/T$/,"",s);  v=(s+0)*1000000000000 }
    else if (s ~ /G$/)  { sub(/G$/,"",s);  v=(s+0)*1000000000 }
    else if (s ~ /M$/)  { sub(/M$/,"",s);  v=(s+0)*1000000 }
    else if (s ~ /k$/)  { sub(/k$/,"",s);  v=(s+0)*1000 }
    else if (s ~ /^[0-9]+(\.[0-9]+)?$/) { v=s+0 }
    else { v=0 }
    printf "%.0f", v }'
}

# The two helpers below read the Deployment's pod template - that is the object
# the task asks you to fix.

# names_of <containers|initContainers> -> one container name per line
names_of(){
  local l="$1"
  k -n "$NS" get deploy "$DEP" -o jsonpath="{range .spec.template.spec.$l[*]}{.name}{\"\n\"}{end}" 2>/dev/null
}

# res_of <list> <container> <requests|limits> <cpu|memory>
res_of(){
  local l="$1" c="$2" kind="$3" r="$4"
  k -n "$NS" get deploy "$DEP" -o jsonpath="{.spec.template.spec.$l[?(@.name==\"$c\")].resources.$kind.$r}" 2>/dev/null
}

# check_pair <label> <list> <container> - the request must exist and must
# equal the limit, numerically.
check_pair(){
  local lbl="$1" list="$2" c="$3" req lim rv lv
  req=$(res_of "$list" "$c" requests cpu)
  lim=$(res_of "$list" "$c" limits cpu)
  nonempty "$lbl '$c' sets a cpu request" "$req"
  if [ -n "$req" ] && [ -n "$lim" ]; then
    rv=$(to_mc "$req"); lv=$(to_mc "$lim")
    if [ "$rv" = "$lv" ]; then
      ok "$lbl '$c' cpu request equals its limit ($req)"
    else
      bad "$lbl '$c' cpu request equals its limit (request '$req' = $rv m, limit '$lim' = $lv m)"
    fi
  else
    bad "$lbl '$c' cpu request equals its limit (request '$req', limit '$lim')"
  fi

  req=$(res_of "$list" "$c" requests memory)
  lim=$(res_of "$list" "$c" limits memory)
  nonempty "$lbl '$c' sets a memory request" "$req"
  if [ -n "$req" ] && [ -n "$lim" ]; then
    rv=$(to_bytes "$req"); lv=$(to_bytes "$lim")
    if [ "$rv" = "$lv" ]; then
      ok "$lbl '$c' memory request equals its limit ($req)"
    else
      bad "$lbl '$c' memory request equals its limit (request '$req' = $rv bytes, limit '$lim' = $lv bytes)"
    fi
  else
    bad "$lbl '$c' memory request equals its limit (request '$req', limit '$lim')"
  fi
}

# ---------------------------------------------------------------------------
# the workload itself
# ---------------------------------------------------------------------------
if ! exists "Deployment $DEP exists in namespace $NS" -n "$NS" deploy "$DEP"; then
  echo; echo -e "${R}v20 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---------------------------------------------------------------------------
# wait for the pod, then take the newest one
# ---------------------------------------------------------------------------
echo "Waiting for the pod to reach the Guaranteed QoS class..."
POD=""
QOS=""
PHASE=""
READY=""
i=0
while [ "$i" -lt 90 ]; do
  LINE=$(k -n "$NS" get pods -l "app=$DEP" \
          -o jsonpath='{range .items[*]}{.metadata.creationTimestamp}{"|"}{.metadata.name}{"|"}{.status.qosClass}{"|"}{.status.phase}{"|"}{.status.containerStatuses[0].ready}{"\n"}{end}' 2>/dev/null \
          | tr -d '\r' | grep -v '^[[:space:]]*$' | LC_ALL=C sort -t'|' -k1,1 | tail -1)
  POD=$(printf '%s' "$LINE" | cut -d'|' -f2)
  QOS=$(printf '%s' "$LINE" | cut -d'|' -f3)
  PHASE=$(printf '%s' "$LINE" | cut -d'|' -f4)
  READY=$(printf '%s' "$LINE" | cut -d'|' -f5)
  if [ "$QOS" = "Guaranteed" ] && [ "$PHASE" = "Running" ] && [ "$READY" = "true" ]; then break; fi
  sleep 2
  i=$((i+2))
done

# ---------------------------------------------------------------------------
# the pod
# ---------------------------------------------------------------------------
echo
echo "-- the running pod --"
if [ -z "$POD" ]; then
  bad "a pod exists for the $DEP deployment"
  skip "the pod is Running"
  skip "the pod runs exactly one container"
  skip "the pod's container is ready"
  skip "the pod's QoS class is Guaranteed"
  skip "the pod still runs an init container"
else
  ok "the pod is $POD"
  eq "the pod is Running" "$PHASE" "Running"

  CTOTAL=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[*].name}' 2>/dev/null \
           | tr -d '\r' | tr ' ' '\n' | grep -c '[^[:space:]]')
  CREADY=$(k -n "$NS" get pod "$POD" -o jsonpath='{range .status.containerStatuses[*]}{.ready}{"\n"}{end}' 2>/dev/null \
           | tr -d '\r' | grep -c '^true$')
  ITOTAL=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.initContainerStatuses[*].name}' 2>/dev/null \
           | tr -d '\r' | tr ' ' '\n' | grep -c '[^[:space:]]')
  eq "the pod runs exactly one container" "$CTOTAL" "1"
  eq "the pod's container is ready" "$CREADY" "1"
  eq "the pod still runs an init container" "$ITOTAL" "1"
  eq "the pod's QoS class is Guaranteed" "$QOS" "Guaranteed"
fi

# ---------------------------------------------------------------------------
# the Deployment template - this is what the task asks you to fix
# ---------------------------------------------------------------------------
echo
echo "-- the Deployment template --"
CNAMES=$(names_of containers     | tr -d '\r' | grep -v '^[[:space:]]*$')
INAMES=$(names_of initContainers | tr -d '\r' | grep -v '^[[:space:]]*$')
NC=$(printf '%s\n' "$CNAMES" | grep -c '[^[:space:]]')
NI=$(printf '%s\n' "$INAMES" | grep -c '[^[:space:]]')

eq "the Deployment still has exactly one main container" "$NC" "1"
if [ "$NI" -ge 1 ] 2>/dev/null; then
  ok "the Deployment still has an init container"
else
  bad "the Deployment still has an init container (got $NI)"
fi

for c in $CNAMES; do
  check_pair "main container" containers "$c"
done
for c in $INAMES; do
  check_pair "init container" initContainers "$c"
done

# ---------------------------------------------------------------------------
# the init container must stay sensible next to the main one
# ---------------------------------------------------------------------------
MAIN=""
for c in $CNAMES; do MAIN="$c"; break; done

if [ -n "$MAIN" ] && [ "$NI" -ge 1 ] 2>/dev/null; then
  MAINMEM=$(res_of containers "$MAIN" limits memory)
  MAINCPU=$(res_of containers "$MAIN" limits cpu)
  for c in $INAMES; do
    IMEM=$(res_of initContainers "$c" limits memory)
    ICPU=$(res_of initContainers "$c" limits cpu)
    if [ -n "$IMEM" ] && [ -n "$MAINMEM" ]; then
      ib=$(to_bytes "$IMEM"); mb=$(to_bytes "$MAINMEM")
      if [ "$ib" -le "$mb" ] 2>/dev/null; then
        ok "init container '$c' memory limit ($IMEM) does not exceed main container '$MAIN' ($MAINMEM)"
      else
        bad "init container '$c' memory limit ($IMEM) does not exceed main container '$MAIN' ($MAINMEM) - $ib bytes vs $mb bytes"
      fi
    else
      bad "init container '$c' memory limit ($IMEM) does not exceed main container '$MAIN' ($MAINMEM)"
    fi
    if [ -n "$ICPU" ] && [ -n "$MAINCPU" ]; then
      ib=$(to_mc "$ICPU"); mb=$(to_mc "$MAINCPU")
      if [ "$ib" -le "$mb" ] 2>/dev/null; then
        ok "init container '$c' cpu limit ($ICPU) does not exceed main container '$MAIN' ($MAINCPU)"
      else
        bad "init container '$c' cpu limit ($ICPU) does not exceed main container '$MAIN' ($MAINCPU) - $ib m vs $mb m"
      fi
    else
      bad "init container '$c' cpu limit ($ICPU) does not exceed main container '$MAIN' ($MAINCPU)"
    fi
  done
fi

note "The QoS class is computed by the kubelet from the pod's resource spec:"
note "Guaranteed means every container - init containers included - has CPU and"
note "memory requests equal to its limits. Burstable means at least one container"
note "has a request but the Guaranteed conditions are not met."
note "The LimitRange filled in the missing requests with defaultRequest values, so"
note "the pod LOOKS like it has requests while they do not match the limits."
note "That is why the class has to be read from the pod's own status."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}v20 PASSED${X}"; else echo -e "${R}v20 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
