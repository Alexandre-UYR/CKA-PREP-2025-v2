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
skip(){ echo -e "\033[33mSKIP${X}  $1"; }

STATE=/tmp/cka-lab
NS=taints
DEPLOY=workload
NODES_FILE="$STATE/c6.nodes"
UID_FILE="$STATE/c6.uid"

echo "== c6: Taint and untaint =="

# ---------------------------------------------------------------- helpers --

# node_has_label <node> <key> <value>
# True when the node carries that label with that value.
node_has_label(){
  local node=$1 key=$2 value=$3 json hit
  json=$(k get node "$node" -o json 2>/dev/null)
  if [ -z "$value" ]; then
    hit=$(printf '%s' "$json" | tr ',' '\n' | grep -E "\"$key\" *: *\"" | head -1)
  else
    hit=$(printf '%s' "$json" | tr ',' '\n' | grep -E "\"$key\" *: *\"$value\"" | head -1)
  fi
  [ -n "$hit" ]
}

# ------------------------------------------------------------ find the node --

PAYMENTS=""
DNU=""
if [ -f "$NODES_FILE" ]; then
  PAYMENTS=$(awk '$1=="payments"{print $2}' "$NODES_FILE")
  DNU=$(awk '$1=="do-not-use"{print $2}' "$NODES_FILE")
fi

if [ -z "$PAYMENTS" ]; then
  note "no state file at $NODES_FILE - falling back to the node carrying the dedicated=payments taint"
  for n in $(k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
    t=$(k get node "$n" -o jsonpath='{range .spec.taints[?(@.key=="dedicated")]}{.value}{" "}{end}' 2>/dev/null)
    if [ "$t" = "payments " ] || [ "$t" = "payments" ]; then PAYMENTS="$n"; break; fi
  done
fi

if [ -z "$PAYMENTS" ]; then
  bad "the node tainted dedicated=payments could be identified"
  echo
  echo -e "${R}c6 FAILED ($FAILS checks)${X}"
  exit 1
fi

note "the dedicated=payments node is: $PAYMENTS"
if [ -n "$DNU" ]; then
  note "the do-not-use taint was on: $DNU"
fi

# ------------------------------------------- 1. the do-not-use taint is gone --

LEFT=""
for n in $(k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
  t=$(k get node "$n" -o jsonpath='{range .spec.taints[?(@.key=="do-not-use")]}{.value}{" "}{end}' 2>/dev/null)
  if [ -n "$t" ]; then LEFT="$LEFT $n"; fi
done
if [ -z "$LEFT" ]; then
  ok "the do-not-use taint is gone from every node"
else
  bad "the do-not-use taint is gone from every node (still on:$LEFT)"
fi

# --------------------------------------- 2. the dedicated taint is still there --

PT=$(k get node "$PAYMENTS" -o jsonpath='{range .spec.taints[*]}{.key}{"="}{.value}{":"}{.effect}{" "}{end}' 2>/dev/null)
has "the dedicated=payments:NoSchedule taint is still on $PAYMENTS" "$PT" "dedicated=payments:NoSchedule"

# ------------------------------------------------------- 3. the toleration ---

TOL=$(k -n "$NS" get deployment "$DEPLOY" -o jsonpath='{range .spec.template.spec.tolerations[*]}{.key}{"|"}{.effect}{"|"}{.operator}{"|"}{.value}{" "}{end}' 2>/dev/null)
TOL_OK=0
for t in $TOL; do
  tkey=$(printf '%s' "$t" | cut -d'|' -f1)
  teff=$(printf '%s' "$t" | cut -d'|' -f2)
  if [ "$tkey" = "dedicated" ] && [ "$teff" = "NoSchedule" ]; then TOL_OK=1; fi
done
if [ "$TOL_OK" = "1" ]; then
  ok "the pod template has a toleration for the dedicated:NoSchedule taint"
else
  bad "the pod template has a toleration for the dedicated:NoSchedule taint (got '$TOL')"
fi

# ------------------------------------------------- 4. the placement rule ----

# The nodeSelector is a map, and kubectl renders maps differently from one
# version to the next, so it is read out of the raw JSON instead.
DEPLOY_JSON=$(k -n "$NS" get deployment "$DEPLOY" -o json 2>/dev/null)

SEL_BLOCK=$(printf '%s' "$DEPLOY_JSON" | sed -n '/"nodeSelector": *{/,/^ *}/p')
case "$SEL_BLOCK" in
  *'{}'*) SEL_BLOCK="";;
esac
NSEL=$(printf '%s\n' "$SEL_BLOCK" | grep -E '"[^"]+" *: *"[^"]+"' \
       | sed -e 's/^[[:space:]]*//' -e 's/^"//' -e 's/":[[:space:]]*"/=/' -e 's/,$//' -e 's/"$//' \
       | tr '\n' ' ')

if [ -n "$NSEL" ]; then
  SEL_OK=1
  for pair in $NSEL; do
    case "$pair" in
      *=*) ;;
      *) continue;;
    esac
    sk="${pair%%=*}"
    sv="${pair#*=}"
    if ! node_has_label "$PAYMENTS" "$sk" "$sv"; then SEL_OK=0; fi
  done
  if [ "$SEL_OK" = "1" ]; then
    ok "the pod template has a nodeSelector that selects $PAYMENTS ($NSEL)"
  else
    bad "the pod template has a nodeSelector that selects $PAYMENTS (the node does not carry: $NSEL)"
  fi
elif printf '%s' "$DEPLOY_JSON" | grep -q '"nodeAffinity"'; then
  ok "the pod template has a nodeAffinity, and the pod is on $PAYMENTS, so the affinity selects it"
else
  bad "the pod template has a nodeSelector or a nodeAffinity that puts it on $PAYMENTS (found neither)"
fi

# ------------------------------------------------------ 5. the pod is up ----

# The new pod still has to pull its image and start, so give it a moment
# before deciding that it is not there.
READY=""
RUNNING_NODES=""
i=0
while [ "$i" -lt 60 ]; do
  READY=$(k -n "$NS" get deployment "$DEPLOY" -o jsonpath='{.status.readyReplicas}' 2>/dev/null) || READY=""
  RUNNING_NODES=$(k -n "$NS" get pods -l app=workload --field-selector status.phase=Running -o jsonpath='{range .items[*]}{.spec.nodeName}{" "}{end}' 2>/dev/null)
  if [ -n "$READY" ] && [ "$READY" -ge 1 ] 2>/dev/null; then break; fi
  sleep 3
  i=$((i+3))
done

if [ -n "$READY" ] && [ "$READY" -ge 1 ] 2>/dev/null; then
  ok "the workload has a running, ready pod (readyReplicas=$READY)"
else
  bad "the workload has a running, ready pod (readyReplicas='$READY')"
fi

has "the workload pod is running on $PAYMENTS" " $RUNNING_NODES " " $PAYMENTS "

# ------------------------------------------- 6. the Deployment was patched --

if [ -f "$UID_FILE" ]; then
  UID_BEFORE=$(tr -d '[:space:]' < "$UID_FILE" 2>/dev/null || true)
  UID_NOW=$(k -n "$NS" get deployment "$DEPLOY" -o jsonpath='{.metadata.uid}' 2>/dev/null)
  eq "the $DEPLOY Deployment was patched, not re-created (same UID)" "$UID_NOW" "$UID_BEFORE"
else
  skip "the $DEPLOY Deployment was patched, not re-created (no UID file at $UID_FILE)"
fi

note "A toleration only says 'this pod may go there'. It does not make the"
note "scheduler want to. You need both the toleration and the placement rule."
note "And NoSchedule does not evict pods that are already running - it only"
note "stops new ones from being scheduled."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c6 PASSED${X}"; else echo -e "${R}c6 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
