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

NS=web
PV=pvvol
PVC=pvc001
DEP=web
SVC=web
LABDIR=/tmp/cka-lab

echo "== w8: A volume with something already on it =="

if ! exists "PersistentVolumeClaim $PVC exists in namespace $NS" -n "$NS" pvc "$PVC"; then
  echo; echo -e "${R}w8 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the claim -------------------------------------------------------------

PHASE=$(k -n "$NS" get pvc "$PVC" -o jsonpath='{.status.phase}' 2>/dev/null)
eq "the claim is Bound" "$PHASE" "Bound"

VN=$(k -n "$NS" get pvc "$PVC" -o jsonpath='{.spec.volumeName}' 2>/dev/null)
eq "the claim is bound to the volume $PV" "$VN" "$PV"

REQ=$(k -n "$NS" get pvc "$PVC" -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null)
eq "the claim requests 200Mi" "$REQ" "200Mi"

MODES=$(k -n "$NS" get pvc "$PVC" -o jsonpath='{.spec.accessModes[*]}' 2>/dev/null)
has "the claim asks for ReadWriteOnce" "$MODES" "ReadWriteOnce"

# The storage class has to be the volume's own, empty string included.
if exists "PersistentVolume $PV still exists" pv "$PV"; then
  PVCLASS=$(k get pv "$PV" -o jsonpath='{.spec.storageClassName}' 2>/dev/null)
  PVCLASS=${PVCLASS:-}
  CLAIMCLASS=$(k -n "$NS" get pvc "$PVC" -o jsonpath='{.spec.storageClassName}' 2>/dev/null)
  CLAIMCLASS=${CLAIMCLASS:-}
  eq "the claim names the same storage class as the volume" "$CLAIMCLASS" "$PVCLASS"

  PVCAP=$(k -n "$NS" get pvc "$PVC" -o jsonpath='{.status.capacity.storage}' 2>/dev/null)
  PVAP=$(k get pv "$PV" -o jsonpath='{.spec.capacity.storage}' 2>/dev/null)
  eq "the bound claim reports the volume's capacity ($PVAP)" "$PVCAP" "$PVAP"

  # The volume has to be the one the setup made - same UID, not a replacement.
  UIDFILE="$LABDIR/w8.pv.uid"
  if [ -f "$UIDFILE" ]; then
    OLDUID=$(cat "$UIDFILE" 2>/dev/null)
    NEWUID=$(k get pv "$PV" -o jsonpath='{.metadata.uid}' 2>/dev/null)
    if [ -n "$OLDUID" ] && [ -n "$NEWUID" ]; then
      eq "the volume was reused, not replaced (same UID)" "$NEWUID" "$OLDUID"
    else
      skip "the recorded or the current volume UID is empty - cannot compare them"
    fi
  else
    skip "no recorded volume UID at $UIDFILE - cannot check that the volume was reused"
  fi
else
  bad "PersistentVolume $PV still exists"
fi

# ---- the Deployment --------------------------------------------------------

if ! exists "Deployment $DEP exists in namespace $NS" -n "$NS" deploy "$DEP"; then
  echo; echo -e "${R}w8 FAILED ($FAILS checks)${X}"; exit 1
fi

FOUND_CLAIM=0
i=0
while :; do
  VNAME=$(k -n "$NS" get deploy "$DEP" -o jsonpath="{.spec.template.spec.volumes[$i].name}" 2>/dev/null)
  [ -n "$VNAME" ] || break
  CLAIM=$(k -n "$NS" get deploy "$DEP" -o jsonpath="{.spec.template.spec.volumes[$i].persistentVolumeClaim.claimName}" 2>/dev/null)
  [ "$CLAIM" = "$PVC" ] && FOUND_CLAIM=1
  i=$((i+1))
done
eq "the Deployment mounts the claim $PVC" "$FOUND_CLAIM" "1"

FOUND_MOUNT=0
ci=0
while :; do
  CNAME=$(k -n "$NS" get deploy "$DEP" -o jsonpath="{.spec.template.spec.containers[$ci].name}" 2>/dev/null)
  [ -n "$CNAME" ] || break
  mi=0
  while :; do
    MNAME=$(k -n "$NS" get deploy "$DEP" -o jsonpath="{.spec.template.spec.containers[$ci].volumeMounts[$mi].name}" 2>/dev/null)
    [ -n "$MNAME" ] || break
    MPATH=$(k -n "$NS" get deploy "$DEP" -o jsonpath="{.spec.template.spec.containers[$ci].volumeMounts[$mi].mountPath}" 2>/dev/null)
    [ "$MPATH" = "/usr/share/nginx/html" ] && FOUND_MOUNT=1
    mi=$((mi+1))
  done
  ci=$((ci+1))
done
eq "the claim is mounted at /usr/share/nginx/html" "$FOUND_MOUNT" "1"

DREADY=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
if [ "${DREADY:-0}" -ge 1 ] 2>/dev/null; then
  ok "the Deployment has a ready replica ($DREADY ready)"
else
  bad "the Deployment has a ready replica (got '${DREADY:-0}')"
fi

# ---- the Service -----------------------------------------------------------

if ! exists "Service $SVC exists in namespace $NS" -n "$NS" svc "$SVC"; then
  echo; echo -e "${R}w8 FAILED ($FAILS checks)${X}"; exit 1
fi

SPORT=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
eq "the Service listens on port 80" "$SPORT" "80"

SELAPP=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.selector.app}' 2>/dev/null)
TMPLAPP=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.template.metadata.labels.app}' 2>/dev/null)
eq "the Service selects the pods the Deployment creates" "$SELAPP" "$TMPLAPP"

EP=$(k -n "$NS" get endpoints "$SVC" -o jsonpath='{range .subsets[*].addresses[*]}{.ip}{"\n"}{end}' 2>/dev/null | grep -c '[0-9]' || true)
if [ "${EP:-0}" -ge 1 ] 2>/dev/null; then
  ok "the Service has endpoints ($EP address(es))"
else
  bad "the Service has endpoints (got ${EP:-0})"
fi

# ---- the live check --------------------------------------------------------
# The point of the question is the file that is ALREADY on the volume: it has
# to be served, not just mounted.

SEED=""
if [ -f "$LABDIR/w8.seed.txt" ]; then
  SEED=$(cat "$LABDIR/w8.seed.txt" 2>/dev/null)
fi

CLUSTERIP=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
BODY=""
FROM=""
if [ -n "$CLUSTERIP" ] && command -v curl >/dev/null 2>&1; then
  BODY=$(curl -s --max-time 12 "http://$CLUSTERIP/" 2>/dev/null || true)
  [ -n "$BODY" ] && FROM="the ClusterIP $CLUSTERIP"
fi

if [ -z "$BODY" ]; then
  # The ClusterIP is not reachable from where the validator runs - ask a pod
  # inside the cluster instead.
  k -n "$NS" delete pod w8-check --ignore-not-found --wait=true --timeout=30s >/dev/null 2>&1 || true
  cat <<EOF | k apply -f - >/dev/null 2>&1 || true
apiVersion: v1
kind: Pod
metadata:
  name: w8-check
  namespace: $NS
spec:
  restartPolicy: Never
  containers:
    - name: check
      image: busybox:1.36
      command:
        - sh
        - -c
        - "wget -O- -T 10 http://$SVC.$NS.svc.cluster.local/ 2>&1 || echo 'THE REQUEST FAILED'"
EOF
  i=0
  while [ "$i" -lt 60 ]; do
    PH=$(k -n "$NS" get pod w8-check -o jsonpath='{.status.phase}' 2>/dev/null || true)
    case "$PH" in Succeeded|Failed) break;; esac
    sleep 2
    i=$((i+2))
  done
  BODY=$(k -n "$NS" logs w8-check 2>/dev/null || true)
  k -n "$NS" delete pod w8-check --ignore-not-found --wait=true --timeout=30s >/dev/null 2>&1 || true
  [ -n "$BODY" ] && FROM="a pod inside the cluster"
fi

if [ -z "$SEED" ]; then
  skip "no seeded content recorded at $LABDIR/w8.seed.txt - cannot compare the served body"
else
  case "$BODY" in
    *"$SEED"*)
      ok "the Service serves the file that was already on the volume (via $FROM)";;
    *)
      bad "the Service serves the file that was already on the volume (via ${FROM:-<nothing>}, body: '${BODY:-<empty>}', wanted: '$SEED')";;
  esac
fi

note "A PV and a PVC bind only when the access modes, the size and the"
note "StorageClass all agree. The request may be SMALLER than the volume -"
note "200Mi against 1Gi binds fine - and the claim then reports the volume's"
note "capacity. The volume's storage class is the empty string, and a claim"
note "that omits the field is defaulted to the cluster's default class."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}w8 PASSED${X}"; else echo -e "${R}w8 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
