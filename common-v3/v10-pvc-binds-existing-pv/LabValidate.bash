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

NS=bind
PV=data-pv
PVC=data
LABDIR="/tmp/cka-lab"

echo "== v10: The claim that will not bind =="

if ! exists "PersistentVolumeClaim $PVC exists in namespace $NS" -n "$NS" pvc "$PVC"; then
  echo; echo -e "${R}v10 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the claim ----

PHASE=$(k -n "$NS" get pvc "$PVC" -o jsonpath='{.status.phase}' 2>/dev/null)
eq "the claim is Bound" "$PHASE" "Bound"

VN=$(k -n "$NS" get pvc "$PVC" -o jsonpath='{.spec.volumeName}' 2>/dev/null)
eq "the claim is bound to the volume $PV" "$VN" "$PV"

SC=$(k -n "$NS" get pvc "$PVC" -o jsonpath='{.spec.storageClassName}' 2>/dev/null)
eq "the claim names the storage class the volume carries" "$SC" "fast"

# ---- the volume ----
# It has to be the same volume: the data on it has to survive, so the candidate
# was told not to delete it. The UID proves it was reused and not replaced.

if ! exists "PersistentVolume $PV still exists" pv "$PV"; then
  echo; echo -e "${R}v10 FAILED ($FAILS checks)${X}"; exit 1
fi

UIDFILE="$LABDIR/v10.pv.uid"
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

CLAIMREF=$(k get pv "$PV" -o jsonpath='{.spec.claimRef.name}' 2>/dev/null)
eq "the volume is claimed by $PVC" "$CLAIMREF" "$PVC"

PVCLASS=$(k get pv "$PV" -o jsonpath='{.spec.storageClassName}' 2>/dev/null)
eq "the volume still carries storage class fast" "$PVCLASS" "fast"

note "A PersistentVolume and a PersistentVolumeClaim bind only when the access modes,"
note "the requested size and the StorageClass all agree. The StorageClass is the one"
note "people miss: a claim that omits it is defaulted to the cluster's default class."
note "The size was 500Mi on both sides and the access modes were ReadWriteOnce - the"
note "classes were the only thing that did not agree."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}v10 PASSED${X}"; else echo -e "${R}v10 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
