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

NS=ephem
POD=eph
VOL=work
LABDIR=/tmp/cka-lab

echo "== w9: A volume that belongs to one Pod =="

if ! exists "Pod $POD exists in namespace $NS" -n "$NS" pod "$POD"; then
  echo; echo -e "${R}w9 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the Pod ---------------------------------------------------------------

PHASE=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null)
eq "the Pod is Running" "$PHASE" "Running"

READY=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
eq "the container is ready" "$READY" "true"

# ---- the volume ------------------------------------------------------------

FOUND_VOL=0
STORAGE=""
MODES=""
IS_EPHEMERAL="no"
IS_CLAIMREF="no"
i=0
while :; do
  VNAME=$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.volumes[$i].name}" 2>/dev/null)
  [ -n "$VNAME" ] || break
  if [ "$VNAME" = "$VOL" ]; then
    FOUND_VOL=1
    STORAGE=$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.volumes[$i].ephemeral.volumeClaimTemplate.spec.resources.requests.storage}" 2>/dev/null)
    MODES=$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.volumes[$i].ephemeral.volumeClaimTemplate.spec.accessModes[*]}" 2>/dev/null)
    EPH=$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.volumes[$i].ephemeral}" 2>/dev/null)
    [ -n "$EPH" ] && IS_EPHEMERAL="yes"
    CREF=$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.volumes[$i].persistentVolumeClaim.claimName}" 2>/dev/null)
    [ -n "$CREF" ] && IS_CLAIMREF="yes"
  fi
  i=$((i+1))
done

eq "the Pod has a volume named $VOL" "$FOUND_VOL" "1"
eq "the volume $VOL is a generic ephemeral volume" "$IS_EPHEMERAL" "yes"
eq "the volume $VOL is not a reference to a claim of your own" "$IS_CLAIMREF" "no"
eq "the volume claim template asks for 500Mi" "$STORAGE" "500Mi"
has "the volume claim template asks for ReadWriteOnce" "$MODES" "ReadWriteOnce"

# ---- where it is mounted ---------------------------------------------------

FOUND_MOUNT=0
ci=0
while :; do
  CNAME=$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.containers[$ci].name}" 2>/dev/null)
  [ -n "$CNAME" ] || break
  mi=0
  while :; do
    MNAME=$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.containers[$ci].volumeMounts[$mi].name}" 2>/dev/null)
    [ -n "$MNAME" ] || break
    MPATH=$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.containers[$ci].volumeMounts[$mi].mountPath}" 2>/dev/null)
    if [ "$MNAME" = "$VOL" ] && [ "$MPATH" = "/work" ]; then FOUND_MOUNT=1; fi
    mi=$((mi+1))
  done
  ci=$((ci+1))
done
eq "the volume $VOL is mounted at /work" "$FOUND_MOUNT" "1"

# ---- the claim the Pod owns ------------------------------------------------

POD_UID=$(k -n "$NS" get pod "$POD" -o jsonpath='{.metadata.uid}' 2>/dev/null)

# The claim's name is generated - it is built from the Pod name and the
# volume name - so it has to be found through its owner.
CLAIM=""
CLAIMS=$(k -n "$NS" get pvc -o jsonpath='{range .items[*]}{.metadata.name}{" "}{range .metadata.ownerReferences[*]}{.kind}{"|"}{.name}{"|"}{.uid}{";"}{end}{"\n"}{end}' 2>/dev/null)
if [ -n "$POD_UID" ]; then
  CLAIM=$(printf '%s\n' "$CLAIMS" | awk -v uid="$POD_UID" '$0 ~ uid {print $1; exit}')
fi

if [ -z "$CLAIM" ]; then
  bad "a PersistentVolumeClaim owned by the Pod exists (found none in namespace $NS)"
  note "The claim is created by the Pod's controller, so it is named after the Pod"
  note "and the volume - something like ${POD}-${VOL}-xxxxx - and it cannot be looked up"
  note "by guessing. Find it through its ownerReferences."
else
  ok "a PersistentVolumeClaim owned by the Pod exists ($CLAIM)"

  OWNERKIND=$(k -n "$NS" get pvc "$CLAIM" -o jsonpath='{.metadata.ownerReferences[?(@.kind=="Pod")].kind}' 2>/dev/null)
  eq "the claim's owner is of kind Pod" "$OWNERKIND" "Pod"

  OWNERNAME=$(k -n "$NS" get pvc "$CLAIM" -o jsonpath='{.metadata.ownerReferences[?(@.kind=="Pod")].name}' 2>/dev/null)
  eq "the claim's owner is the Pod $POD" "$OWNERNAME" "$POD"

  OWNERUID=$(k -n "$NS" get pvc "$CLAIM" -o jsonpath='{.metadata.ownerReferences[?(@.kind=="Pod")].uid}' 2>/dev/null)
  eq "the claim's owner is this Pod (same UID)" "$OWNERUID" "$POD_UID"

  CPHASE=$(k -n "$NS" get pvc "$CLAIM" -o jsonpath='{.status.phase}' 2>/dev/null)
  eq "the claim is Bound" "$CPHASE" "Bound"

  CREQ=$(k -n "$NS" get pvc "$CLAIM" -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null)
  eq "the claim requests 500Mi" "$CREQ" "500Mi"

  CMODES=$(k -n "$NS" get pvc "$CLAIM" -o jsonpath='{.spec.accessModes[*]}' 2>/dev/null)
  has "the claim asks for ReadWriteOnce" "$CMODES" "ReadWriteOnce"
fi

note "A generic ephemeral volume is a Pod-local claim. The Pod's controller"
note "creates it when the Pod is scheduled, and the garbage collector removes"
note "it when the Pod is deleted - which is why the claim is owned by the Pod"
note "and not by the namespace."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}w9 PASSED${X}"; else echo -e "${R}w9 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
