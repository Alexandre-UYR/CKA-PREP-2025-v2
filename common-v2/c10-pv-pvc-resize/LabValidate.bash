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

# Kubernetes quantity to bytes, so two sizes can be compared.
qbytes(){
  local q="$1" num unit mult
  num=$(printf '%s' "$q" | sed 's/[^0-9].*$//')
  unit=$(printf '%s' "$q" | sed 's/^[0-9]*//')
  if [ -z "$num" ]; then num=0; fi
  case "$unit" in
    Ki) mult=1024 ;;
    Mi) mult=$((1024*1024)) ;;
    Gi) mult=$((1024*1024*1024)) ;;
    Ti) mult=$((1024*1024*1024*1024)) ;;
    k)  mult=1000 ;;
    M)  mult=$((1000*1000)) ;;
    G)  mult=$((1000*1000*1000)) ;;
    *)  mult=1 ;;
  esac
  printf '%s' "$((num * mult))"
}

NS=resize
PV=expand-pv
PVC=expand-pvc
SC=expandable

echo "== c10: Expand a PersistentVolumeClaim =="

if ! exists "PersistentVolume $PV exists" pv "$PV"; then
  echo; echo -e "${R}c10 FAILED ($FAILS checks)${X}"; exit 1
fi
if ! exists "PersistentVolumeClaim $PVC exists in namespace $NS" -n "$NS" pvc "$PVC"; then
  echo; echo -e "${R}c10 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the volume ----
PVCAP=$(k get pv "$PV" -o jsonpath='{.spec.capacity.storage}' 2>/dev/null)
eq "the PersistentVolume has a capacity of 100Mi" "$PVCAP" "100Mi"

PVAM=$(k get pv "$PV" -o jsonpath='{.spec.accessModes[*]}' 2>/dev/null)
has "the PersistentVolume allows ReadWriteOnce" " $PVAM " " ReadWriteOnce "

PVSC=$(k get pv "$PV" -o jsonpath='{.spec.storageClassName}' 2>/dev/null)
eq "the PersistentVolume uses the $SC StorageClass" "$PVSC" "$SC"

PVHP=$(k get pv "$PV" -o jsonpath='{.spec.hostPath.path}' 2>/dev/null)
eq "the PersistentVolume is a hostPath at /tmp/expand-data" "$PVHP" "/tmp/expand-data"

# ---- the claim ----
PHASE=$(k -n "$NS" get pvc "$PVC" -o jsonpath='{.status.phase}' 2>/dev/null)
eq "the claim is Bound" "$PHASE" "Bound"

CLSC=$(k -n "$NS" get pvc "$PVC" -o jsonpath='{.spec.storageClassName}' 2>/dev/null)
eq "the claim names the $SC StorageClass" "$CLSC" "$SC"

CLAM=$(k -n "$NS" get pvc "$PVC" -o jsonpath='{.spec.accessModes[*]}' 2>/dev/null)
has "the claim allows ReadWriteOnce" " $CLAM " " ReadWriteOnce "

VOL=$(k -n "$NS" get pvc "$PVC" -o jsonpath='{.spec.volumeName}' 2>/dev/null)
eq "the claim is bound to the volume $PV" "$VOL" "$PV"

REQ=$(k -n "$NS" get pvc "$PVC" -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null)
eq "the claim requests 70Mi after the expansion" "$REQ" "70Mi"

CAP=$(k -n "$NS" get pvc "$PVC" -o jsonpath='{.status.capacity.storage}' 2>/dev/null)
nonempty "the claim reports a capacity" "$CAP"
if [ "$(qbytes "$CAP")" -ge "$(qbytes "$REQ")" ]; then
  ok "the claim's reported capacity covers the expanded request (got '$CAP')"
else
  bad "the claim's reported capacity covers the expanded request (got '$CAP', want at least '$REQ')"
fi

# ---- the class the expansion depends on ----
if ! exists "StorageClass $SC exists" sc "$SC"; then
  echo; echo -e "${R}c10 FAILED ($FAILS checks)${X}"; exit 1
fi
ALLOW=$(k get sc "$SC" -o jsonpath='{.allowVolumeExpansion}' 2>/dev/null)
eq "the $SC StorageClass allows volume expansion" "$ALLOW" "true"

note "The claim's reported capacity is the capacity of the volume it is bound"
note "to, and hostPath has no resizing support, so the backend has nothing to"
note "grow: the 100Mi volume already covers the 70Mi request. On a driver that"
note "does support resizing the reported capacity would be exactly 70Mi."
note "What proves the expansion was accepted is the request itself: the API"
note "server refuses to enlarge a bound claim whose StorageClass does not"
note "allow expansion, so a request of 70Mi only survives if the claim names a"
note "class that allows it."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c10 PASSED${X}"; else echo -e "${R}c10 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
