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

NS=agent
DS=fluentd
LABDIR=/tmp/cka-lab

echo "== w7: One pod on every node =="

if ! exists "DaemonSet $DS exists in namespace $NS" -n "$NS" daemonset "$DS"; then
  echo; echo -e "${R}w7 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the cluster ------------------------------------------------------------

NODES_TOTAL=$(k get nodes --no-headers 2>/dev/null | grep -c . || true)
NODES_TOTAL=${NODES_TOTAL:-0}
NODES_READY=$(k get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | grep -c . || true)
NODES_READY=${NODES_READY:-0}
nonempty "the cluster reports at least one node" "$NODES_TOTAL"

# ---- the image --------------------------------------------------------------

IMAGES=""
i=0
while :; do
  CNAME=$(k -n "$NS" get ds "$DS" -o jsonpath="{.spec.template.spec.containers[$i].name}" 2>/dev/null)
  [ -n "$CNAME" ] || break
  CIMG=$(k -n "$NS" get ds "$DS" -o jsonpath="{.spec.template.spec.containers[$i].image}" 2>/dev/null)
  IMAGES="$IMAGES $CIMG"
  i=$((i+1))
done
has "the DaemonSet runs quay.io/fluentd/fluentd:v1.6" "$IMAGES" "quay.io/fluentd/fluentd:v1.6"

# ---- hostNetwork ------------------------------------------------------------

HN=$(k -n "$NS" get ds "$DS" -o jsonpath='{.spec.template.spec.hostNetwork}' 2>/dev/null)
eq "the pod template sets hostNetwork: true" "$HN" "true"

# ---- the hostPath volumes ---------------------------------------------------

FOUND_VARLOG=0
FOUND_VARLIB=0
HP_COUNT=0
i=0
while :; do
  VNAME=$(k -n "$NS" get ds "$DS" -o jsonpath="{.spec.template.spec.volumes[$i].name}" 2>/dev/null)
  [ -n "$VNAME" ] || break
  HPATH=$(k -n "$NS" get ds "$DS" -o jsonpath="{.spec.template.spec.volumes[$i].hostPath.path}" 2>/dev/null)
  if [ -n "$HPATH" ]; then
    HP_COUNT=$((HP_COUNT+1))
    case "$VNAME|$HPATH" in
      "varlog|/var/log") FOUND_VARLOG=1;;
      "varlibdockercontainers|/var/lib/docker/containers") FOUND_VARLIB=1;;
      *) bad "the pod template has no hostPath volume $VNAME at $HPATH";;
    esac
  fi
  i=$((i+1))
done

eq "the pod template has exactly two hostPath volumes" "$HP_COUNT" "2"
eq "the varlog volume uses the host path /var/log" "$FOUND_VARLOG" "1"
eq "the varlibdockercontainers volume uses the host path /var/lib/docker/containers" "$FOUND_VARLIB" "1"

# ---- where they are mounted -------------------------------------------------

MOUNT_VARLOG=0
MOUNT_VARLIB=0
ci=0
while :; do
  CNAME=$(k -n "$NS" get ds "$DS" -o jsonpath="{.spec.template.spec.containers[$ci].name}" 2>/dev/null)
  [ -n "$CNAME" ] || break
  mi=0
  while :; do
    MNAME=$(k -n "$NS" get ds "$DS" -o jsonpath="{.spec.template.spec.containers[$ci].volumeMounts[$mi].name}" 2>/dev/null)
    [ -n "$MNAME" ] || break
    MPATH=$(k -n "$NS" get ds "$DS" -o jsonpath="{.spec.template.spec.containers[$ci].volumeMounts[$mi].mountPath}" 2>/dev/null)
    case "$MNAME|$MPATH" in
      "varlog|/var/log") MOUNT_VARLOG=1;;
      "varlibdockercontainers|/var/lib/docker/containers") MOUNT_VARLIB=1;;
    esac
    mi=$((mi+1))
  done
  ci=$((ci+1))
done

eq "the varlog volume is mounted at /var/log" "$MOUNT_VARLOG" "1"
eq "the varlibdockercontainers volume is mounted at /var/lib/docker/containers" "$MOUNT_VARLIB" "1"

# The type matters on a containerd node, where /var/lib/docker/containers does
# not exist. It is reported, not failed: the pods being Ready is the proof.
ci=0
while :; do
  CNAME=$(k -n "$NS" get ds "$DS" -o jsonpath="{.spec.template.spec.containers[$ci].name}" 2>/dev/null)
  [ -n "$CNAME" ] || break
  ci=$((ci+1))
done
i=0
TYPED=""
while :; do
  VNAME=$(k -n "$NS" get ds "$DS" -o jsonpath="{.spec.template.spec.volumes[$i].name}" 2>/dev/null)
  [ -n "$VNAME" ] || break
  VTYPE=$(k -n "$NS" get ds "$DS" -o jsonpath="{.spec.template.spec.volumes[$i].hostPath.type}" 2>/dev/null)
  TYPED="$TYPED $VNAME=${VTYPE:-<unset>}"
  i=$((i+1))
done
case "$TYPED" in
  *varlibdockercontainers=DirectoryOrCreate*)
    note "the varlibdockercontainers volume uses hostPath.type DirectoryOrCreate";;
  *)
    note "the hostPath types are:$TYPED"
    note "DirectoryOrCreate is the one that lets the kubelet create the directory"
    note "on a containerd node, where /var/lib/docker/containers does not exist";;
esac

# ---- the toleration ---------------------------------------------------------

RECKEY=""
RECEFF=""
if [ -f "$LABDIR/w7.taint" ]; then
  RECKEY=$(cut -d: -f1 "$LABDIR/w7.taint" 2>/dev/null)
  RECEFF=$(cut -d: -f2 "$LABDIR/w7.taint" 2>/dev/null)
fi

if [ -z "$RECKEY" ]; then
  skip "the cluster has no tainted control-plane node - there is nothing to tolerate"
else
  TOL_OK=0
  TOL_KEYS=""
  TOLS=$(k -n "$NS" get ds "$DS" -o jsonpath='{range .spec.template.spec.tolerations[*]}{.key}{"|"}{.effect}{"|"}{.operator}{"\n"}{end}' 2>/dev/null)
  while IFS='|' read -r tkey teff top; do
    TOL_KEYS="$TOL_KEYS ${tkey:-<empty>}:${teff:-<none>}"
    # A toleration with no key and operator Exists tolerates every taint.
    if [ -z "$tkey" ] && [ "$top" = "Exists" ]; then
      TOL_OK=1
      continue
    fi
    case "$tkey" in
      node-role.kubernetes.io/control-plane|node-role.kubernetes.io/master|"$RECKEY")
        if [ -z "$teff" ] || [ "$teff" = "NoSchedule" ] || { [ -n "$RECEFF" ] && [ "$teff" = "$RECEFF" ]; }; then
          TOL_OK=1
        fi
        ;;
    esac
  done <<EOF
$TOLS
EOF

  if [ "$TOL_OK" -eq 1 ]; then
    ok "the pod template tolerates the control-plane taint ($RECKEY:$RECEFF)"
  else
    bad "the pod template tolerates the control-plane taint (tolerations:${TOL_KEYS:- <none>})"
  fi
fi

# ---- the scheduling result --------------------------------------------------

echo "Waiting for the DaemonSet controller to settle..."
i=0
while [ "$i" -lt 30 ]; do
  DESIRED=$(k -n "$NS" get ds "$DS" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)
  READY=$(k -n "$NS" get ds "$DS" -o jsonpath='{.status.numberReady}' 2>/dev/null)
  if [ -n "$DESIRED" ] && [ -n "$READY" ] && [ "$DESIRED" = "$READY" ]; then break; fi
  sleep 2
  i=$((i+2))
done

DESIRED=$(k -n "$NS" get ds "$DS" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)
READY=$(k -n "$NS" get ds "$DS" -o jsonpath='{.status.numberReady}' 2>/dev/null)

EXPECTED=$NODES_TOTAL
if [ "$NODES_READY" != "$NODES_TOTAL" ]; then
  EXPECTED=$NODES_READY
  note "$((NODES_TOTAL - NODES_READY)) node(s) are not Ready; the DaemonSet controller does not place"
  note "pods on them, so DESIRED is compared against the $NODES_READY Ready node(s)."
fi

eq "the DaemonSet wants a pod on every node (desiredNumberScheduled)" "$DESIRED" "$EXPECTED"
eq "every pod it wants is Ready (numberReady)" "$READY" "$DESIRED"

# ---- every pod of the DaemonSet ---------------------------------------------

DS_UID=$(k -n "$NS" get ds "$DS" -o jsonpath='{.metadata.uid}' 2>/dev/null)
PODS=$(k -n "$NS" get pods \
        -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{range .metadata.ownerReferences[*]}{.uid}{","}{end}{"\n"}{end}' \
        2>/dev/null | awk -F'|' -v u="$DS_UID" '$2 ~ u {print $1}')

set -- $PODS
POD_COUNT=$#
eq "the DaemonSet has one pod per node" "$POD_COUNT" "$EXPECTED"

for p in "$@"; do
  PR=$(k -n "$NS" get pod "$p" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  eq "pod $p is Ready" "$PR" "True"
done

note "A DaemonSet is placed by the DaemonSet controller, not by the default scheduler."
note "It ignores a node's unschedulable flag, but it does respect taints: the"
note "control-plane node needs a toleration or it is skipped there."
note "A hostPath resolves on the NODE - the path is on the node, the mountPath"
note "is inside the container."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}w7 PASSED${X}"; else echo -e "${R}w7 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
