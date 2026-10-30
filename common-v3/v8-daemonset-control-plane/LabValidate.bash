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

NS=ds
DS=agent
LABDIR="/tmp/cka-lab"

echo "== v8: One pod per node, including the control plane =="

if ! exists "DaemonSet $DS exists in namespace $NS" -n "$NS" daemonset "$DS"; then
  echo; echo -e "${R}v8 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the cluster ----

NODES=$(k get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | wc -w | tr -d ' ')
nonempty "the cluster reports at least one node" "$NODES"

# ---- hostNetwork ----

HN=$(k -n "$NS" get daemonset "$DS" -o jsonpath='{.spec.template.spec.hostNetwork}' 2>/dev/null)
eq "the pod template sets hostNetwork: true" "$HN" "true"

# ---- the control-plane toleration ----
# The setup recorded the taint the cluster actually carries. The standard
# control-plane key is always accepted; the master key is accepted too, for
# clusters that still taint the control plane the old way.

RECKEY=""
[ -f "$LABDIR/v8.taint" ] && RECKEY="$(cat "$LABDIR/v8.taint" 2>/dev/null)"
RECKEY="${RECKEY%%:*}"

TOL_KEYS=""
TOL_EFFECTS=""
TOL_OK=0
i=0
while :; do
  TKEY=$(k -n "$NS" get daemonset "$DS" -o jsonpath="{.spec.template.spec.tolerations[$i].key}" 2>/dev/null)
  [ -n "$TKEY" ] || break
  TEFF=$(k -n "$NS" get daemonset "$DS" -o jsonpath="{.spec.template.spec.tolerations[$i].effect}" 2>/dev/null)
  TOL_KEYS="$TOL_KEYS $TKEY"
  TOL_EFFECTS="$TOL_EFFECTS ${TEFF:-<none>}"
  case "$TKEY" in
    node-role.kubernetes.io/control-plane|node-role.kubernetes.io/master)
      # An empty effect tolerates every effect; NoSchedule covers the node's taint.
      if [ -z "$TEFF" ] || [ "$TEFF" = "NoSchedule" ]; then TOL_OK=1; fi
      ;;
  esac
  if [ -n "$RECKEY" ] && [ "$TKEY" = "$RECKEY" ]; then
    if [ -z "$TEFF" ] || [ "$TEFF" = "NoSchedule" ]; then TOL_OK=1; fi
  fi
  i=$((i+1))
done

if [ "$TOL_OK" -eq 1 ]; then
  ok "the pod template tolerates the control-plane taint"
else
  bad "the pod template tolerates the control-plane taint (found keys:${TOL_KEYS:- <none>} effects:${TOL_EFFECTS:- <none>})"
fi

# ---- the scheduling result ----
# Give the DaemonSet controller a moment to update its status.

echo "Waiting for the DaemonSet controller to settle..."
i=0
while [ "$i" -lt 30 ]; do
  DESIRED=$(k -n "$NS" get daemonset "$DS" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)
  READY=$(k -n "$NS" get daemonset "$DS" -o jsonpath='{.status.numberReady}' 2>/dev/null)
  if [ -n "$DESIRED" ] && [ -n "$READY" ] && [ "$DESIRED" = "$READY" ]; then break; fi
  sleep 2
  i=$((i+2))
done

DESIRED=$(k -n "$NS" get daemonset "$DS" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)
READY=$(k -n "$NS" get daemonset "$DS" -o jsonpath='{.status.numberReady}' 2>/dev/null)

eq "the DaemonSet wants a pod on every node (desiredNumberScheduled)" "$DESIRED" "$NODES"
eq "every pod it wants is Ready (numberReady)" "$READY" "$DESIRED"

# ---- every pod of the DaemonSet ----

DS_UID=$(k -n "$NS" get daemonset "$DS" -o jsonpath='{.metadata.uid}' 2>/dev/null)
PODS=$(k -n "$NS" get pods \
        -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{range .metadata.ownerReferences[*]}{.uid}{","}{end}{"\n"}{end}' \
        2>/dev/null | awk -F'|' -v u="$DS_UID" '$2 ~ u {print $1}')

set -- $PODS
POD_COUNT=$#
eq "the DaemonSet has one pod per node" "$POD_COUNT" "$NODES"

for p in "$@"; do
  PR=$(k -n "$NS" get pod "$p" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  eq "pod $p is Ready" "$PR" "True"
done

note "A DaemonSet is placed by the DaemonSet controller, not the default scheduler."
note "The controller wants a pod on EVERY node - it does not honour the taint - so the"
note "pod on the tainted node exists but stays Pending until the template tolerates it."
note "A nodeSelector is the easy way to fail this: it drops the DaemonSet off every node"
note "the selector does not match, and DESIRED stops being the number of nodes."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}v8 PASSED${X}"; else echo -e "${R}v8 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
