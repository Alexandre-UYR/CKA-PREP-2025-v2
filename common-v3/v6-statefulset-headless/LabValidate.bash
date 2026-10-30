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

NS=stateful
SS=web
SVC=web-headless

# storage in bytes, so 1Gi and 1024Mi compare equal
to_bytes(){
  printf '%s' "$1" | awk '{
    s=$0
    if (s ~ /Gi$/)       { sub(/Gi$/,"",s); v=s*1024*1024*1024 }
    else if (s ~ /Mi$/)  { sub(/Mi$/,"",s); v=s*1024*1024 }
    else if (s ~ /Ki$/)  { sub(/Ki$/,"",s); v=s*1024 }
    else if (s ~ /Ti$/)  { sub(/Ti$/,"",s); v=s*1024*1024*1024*1024 }
    else if (s ~ /G$/)   { sub(/G$/,"",s);  v=s*1000000000 }
    else if (s ~ /M$/)   { sub(/M$/,"",s);  v=s*1000000 }
    else if (s ~ /k$/)   { sub(/k$/,"",s);  v=s*1000 }
    else                 { v=s }
    printf "%d", v
  }'
}

echo "== v6: Give each pod its own identity and its own disk =="

if ! exists "StatefulSet $SS exists in namespace $NS" -n "$NS" statefulset "$SS"; then
  echo; echo -e "${R}v6 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- serviceName and replicas ----------------------------------------------

SVC_NAME=$(k -n "$NS" get statefulset "$SS" -o jsonpath='{.spec.serviceName}' 2>/dev/null)
eq "the StatefulSet's serviceName is $SVC" "$SVC_NAME" "$SVC"

REPLICAS=$(k -n "$NS" get statefulset "$SS" -o jsonpath='{.spec.replicas}' 2>/dev/null)
eq "the StatefulSet runs 3 replicas" "$REPLICAS" "3"

# ---- the headless Service it is governed by --------------------------------

CIP=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
eq "the Service $SVC is headless (clusterIP None)" "$CIP" "None"

# ---- exactly one volumeClaimTemplate ---------------------------------------

TPL_COUNT=$(k -n "$NS" get statefulset "$SS" \
              -o jsonpath='{range .spec.volumeClaimTemplates[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -c .)
eq "the StatefulSet has exactly one volumeClaimTemplate" "$TPL_COUNT" "1"

STORAGE=$(k -n "$NS" get statefulset "$SS" \
            -o jsonpath='{.spec.volumeClaimTemplates[0].spec.resources.requests.storage}' 2>/dev/null)
eq "the claim template asks for 1Gi of storage" "$(to_bytes "$STORAGE")" "1073741824"

ACCESS=$(k -n "$NS" get statefulset "$SS" \
           -o jsonpath='{.spec.volumeClaimTemplates[0].spec.accessModes[*]}' 2>/dev/null)
has "the claim template uses the ReadWriteOnce access mode" "$ACCESS" "ReadWriteOnce"

# ---- the StorageClass, looked up live --------------------------------------

DEFAULT_SC=$(k get storageclass \
  -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -1)
CLAIM_SC=$(k -n "$NS" get statefulset "$SS" \
             -o jsonpath='{.spec.volumeClaimTemplates[0].spec.storageClassName}' 2>/dev/null)

if [ -z "$DEFAULT_SC" ]; then
  skip "the claim template uses the default StorageClass (this cluster has no default StorageClass)"
  nonempty "the claim template names a StorageClass" "$CLAIM_SC"
else
  eq "the claim template uses the default StorageClass ($DEFAULT_SC)" "$CLAIM_SC" "$DEFAULT_SC"
fi

# ---- the three pods --------------------------------------------------------

echo "Waiting for the three pods to be Ready (up to 120s)..."
i=0
while [ "$i" -lt 120 ]; do
  R0=$(k -n "$NS" get pod web-0 -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
  R1=$(k -n "$NS" get pod web-1 -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
  R2=$(k -n "$NS" get pod web-2 -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
  if [ "$R0" = "true" ] && [ "$R1" = "true" ] && [ "$R2" = "true" ]; then break; fi
  sleep 3
  i=$((i+3))
done

CLAIMS=""
for p in web-0 web-1 web-2; do
  if ! k -n "$NS" get pod "$p" >/dev/null 2>&1; then
    bad "pod $p exists in namespace $NS"
    continue
  fi
  ok "pod $p exists in namespace $NS"
  READY=$(k -n "$NS" get pod "$p" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
  eq "pod $p is Ready" "$READY" "true"
  C=$(k -n "$NS" get pod "$p" \
        -o jsonpath='{range .spec.volumes[*]}{.persistentVolumeClaim.claimName}{"\n"}{end}' 2>/dev/null \
        | grep -v '^[[:space:]]*$' | tr '\n' ' ')
  if [ -n "$C" ]; then
    ok "pod $p has its own volume claim (${C% })"
  else
    bad "pod $p has its own volume claim (it has none)"
  fi
  CLAIMS="$CLAIMS $C"
done

# ---- each claim bound ------------------------------------------------------

echo "Waiting for the claims to be Bound (up to 60s)..."
i=0
while [ "$i" -lt 60 ]; do
  ALLBOUND=1
  for c in $(printf '%s\n' $CLAIMS | sort -u); do
    [ -n "$c" ] || continue
    P=$(k -n "$NS" get pvc "$c" -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$P" != "Bound" ]; then ALLBOUND=0; fi
  done
  [ "$ALLBOUND" -eq 1 ] && break
  sleep 3
  i=$((i+3))
done

for c in $(printf '%s\n' $CLAIMS | sort -u); do
  [ -n "$c" ] || continue
  if ! k -n "$NS" get pvc "$c" >/dev/null 2>&1; then
    bad "the claim $c exists"
    continue
  fi
  ok "the claim $c exists"
  PH=$(k -n "$NS" get pvc "$c" -o jsonpath='{.status.phase}' 2>/dev/null)
  eq "the claim $c is Bound" "$PH" "Bound"
done

DISTINCT=$(printf '%s\n' $CLAIMS | sort -u | grep -c .)
eq "each pod has its own claim (three distinct claims)" "$DISTINCT" "3"

note "The claim names are <claimTemplateName>-<statefulSetName>-<ordinal>, so the"
note "template name is the candidate's choice - the validator finds the claims"
note "through the pods' volumes rather than by name."

if k -n "$NS" get deploy "$SS" >/dev/null 2>&1; then
  note "The plain Deployment '$SS' is still in the namespace. It shares the"
  note "label selector with the StatefulSet, so it is worth deleting it."
fi

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}v6 PASSED${X}"; else echo -e "${R}v6 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
