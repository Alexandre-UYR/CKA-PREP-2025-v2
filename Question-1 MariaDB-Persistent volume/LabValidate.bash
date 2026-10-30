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

NS=mariadb
UID_FILE=/tmp/cka-lab/q1.pv.uid

echo "== Q1: MariaDB persistent volume =="

# --- The PVC the candidate had to create ---------------------------------
exists "PVC mariadb exists in namespace $NS" pvc mariadb -n "$NS"
PVC_PHASE="$(k get pvc mariadb -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null)"
eq "PVC mariadb is Bound" "$PVC_PHASE" "Bound"
PVC_SIZE="$(k get pvc mariadb -n "$NS" -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null)"
eq "PVC mariadb requests 250Mi of storage" "$PVC_SIZE" "250Mi"
PVC_MODE="$(k get pvc mariadb -n "$NS" -o jsonpath='{.spec.accessModes[0]}' 2>/dev/null)"
eq "PVC mariadb uses access mode ReadWriteOnce" "$PVC_MODE" "ReadWriteOnce"
PVC_PV="$(k get pvc mariadb -n "$NS" -o jsonpath='{.spec.volumeName}' 2>/dev/null)"
eq "PVC mariadb is bound to the pre-existing PV mariadb-pv" "$PVC_PV" "mariadb-pv"

# --- The pre-existing PV must be reused, not replaced --------------------
exists "PV mariadb-pv still exists" pv mariadb-pv
PV_POLICY="$(k get pv mariadb-pv -o jsonpath='{.spec.persistentVolumeReclaimPolicy}' 2>/dev/null)"
eq "PV mariadb-pv still has reclaim policy Retain" "$PV_POLICY" "Retain"

if [ -f "$UID_FILE" ]; then
  SETUP_UID="$(cat "$UID_FILE" 2>/dev/null)"
  NOW_UID="$(k get pv mariadb-pv -o jsonpath='{.metadata.uid}' 2>/dev/null)"
  eq "PV mariadb-pv is the SAME PV created during setup (uid unchanged, so it was reused and not re-created)" "$NOW_UID" "$SETUP_UID"
else
  bad "PV mariadb-pv is the SAME PV created during setup (uid file $UID_FILE is missing - re-run the setup)"
fi

PV_COUNT="$(k get pv -o name 2>/dev/null | grep -c .)"
eq "Exactly one PersistentVolume exists in the cluster" "${PV_COUNT:-0}" "1"

# --- The deployment the candidate had to bring back -----------------------
exists "Deployment mariadb exists in namespace $NS" deploy mariadb -n "$NS"
REP="$(k get deploy mariadb -n "$NS" -o jsonpath='{.spec.replicas}' 2>/dev/null)"
eq "Deployment mariadb runs 1 replica" "$REP" "1"
IMG="$(k get deploy mariadb -n "$NS" -o jsonpath='{.spec.template.spec.containers[?(@.name=="mariadb")].image}' 2>/dev/null)"
has "Container mariadb runs a mariadb image" "$IMG" "mariadb"
READY="$(k get deploy mariadb -n "$NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"
eq "Deployment mariadb has 1 ready replica" "$READY" "1"
ENVNAME="$(k get deploy mariadb -n "$NS" -o jsonpath='{.spec.template.spec.containers[?(@.name=="mariadb")].env[?(@.name=="MYSQL_ROOT_PASSWORD")].name}' 2>/dev/null)"
has "Container mariadb defines env var MYSQL_ROOT_PASSWORD" "$ENVNAME" "MYSQL_ROOT_PASSWORD"

MOUNTVOL="$(k get deploy mariadb -n "$NS" -o jsonpath='{.spec.template.spec.containers[?(@.name=="mariadb")].volumeMounts[?(@.mountPath=="/var/lib/mysql")].name}' 2>/dev/null)"
nonempty "Container mariadb mounts a volume at /var/lib/mysql" "$MOUNTVOL"
CLAIM=""
if [ -n "$MOUNTVOL" ]; then
  CLAIM="$(k get deploy mariadb -n "$NS" -o jsonpath="{.spec.template.spec.volumes[?(@.name==\"$MOUNTVOL\")].persistentVolumeClaim.claimName}" 2>/dev/null)"
fi
eq "Deployment volume '$MOUNTVOL' points at PVC mariadb (claimName must not be empty)" "$CLAIM" "mariadb"

# --- The running pod must really mount that claim ------------------------
POD="$(k get pods -n "$NS" -l app=mariadb -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
nonempty "A pod of the mariadb deployment exists" "$POD"
POD_CLAIM="$(k get pods -n "$NS" -l app=mariadb -o jsonpath='{.items[0].spec.volumes[*].persistentVolumeClaim.claimName}' 2>/dev/null)"
has "The running pod mounts the mariadb PVC" "$POD_CLAIM" "mariadb"

# --- The data has to still be there ---------------------------------------
DATADIR="$(k -n "$NS" exec deploy/mariadb -- ls /var/lib/mysql 2>/dev/null)"
nonempty "MariaDB data directory /var/lib/mysql is not empty (an empty datadir means the volume was re-created instead of reused)" "$DATADIR"
has "MariaDB system database directory 'mysql' is present in /var/lib/mysql" "$DATADIR" "mysql"

if [ "$FAILS" -eq 0 ]; then echo -e "${G}Q1 PASSED${X}"; else echo -e "${R}Q1 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
