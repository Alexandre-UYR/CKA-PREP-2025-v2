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

NS=shop
DEP=cart
SVC=cart-svc
LABDIR=/tmp/cka-lab

echo "== x15: The Service that selects nothing =="

if ! exists "namespace $NS exists" namespace "$NS"; then
  echo; echo -e "${R}x15 FAILED ($FAILS checks)${X}"; exit 1
fi

if ! exists "Service $SVC exists in namespace $NS" -n "$NS" svc "$SVC"; then
  echo; echo -e "${R}x15 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---------------------------------------------------------------------------
# the Service is the one that was there at setup: it was edited in place
# ---------------------------------------------------------------------------
ORIG=$(cat "$LABDIR/x15.svc.uid" 2>/dev/null || true)
NOW=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.metadata.uid}' 2>/dev/null || true)
if [ -z "$ORIG" ]; then
  bad "the Service was edited in place, not re-created (no UID was recorded at setup)"
elif [ "$ORIG" = "$NOW" ]; then
  ok "the Service was edited in place, not re-created (its UID is unchanged)"
else
  bad "the Service was edited in place, not re-created (its UID changed - it was deleted and re-created)"
fi

# ---------------------------------------------------------------------------
# the pods of the Deployment
# ---------------------------------------------------------------------------
# The pods that belong to the Deployment: the ones owned by a ReplicaSet.
PAIRS=$(k -n "$NS" get pods -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.ownerReferences[0].kind}{"\n"}{end}' 2>/dev/null) || PAIRS=""
PODS=$(printf '%s\n' "$PAIRS" | grep ' ReplicaSet$' | cut -d' ' -f1)
NPODS=$(printf '%s\n' "$PODS" | grep -c '[^[:space:]]') || NPODS=0

# the pods still carry app=cart-v2
WRONGLABEL=""
for p in $PODS; do
  L=$(k -n "$NS" get pod "$p" -o jsonpath='{.metadata.labels.app}' 2>/dev/null)
  [ "$L" = "cart-v2" ] || WRONGLABEL="$WRONGLABEL $p=$L"
done
if [ -z "$WRONGLABEL" ] && [ "$NPODS" -ge 2 ]; then
  ok "the pods still carry the label app=cart-v2 ($NPODS pods)"
else
  bad "the pods still carry the label app=cart-v2 (wrong or missing:$WRONGLABEL)"
fi

# ---------------------------------------------------------------------------
# the Service's selector now matches the pods
# ---------------------------------------------------------------------------
SEL=$(k -n "$NS" get svc "$SVC" -o go-template='{{range $k, $v := .spec.selector}}{{$k}}={{$v}} {{end}}' 2>/dev/null)
if [ -z "$(printf '%s' "$SEL" | tr -d ' ')" ]; then
  bad "the Service's selector matches the pods' labels (it has no selector at all, so it selects everything in the namespace)"
else
  FIRSTPOD=$(printf '%s\n' "$PODS" | grep -m1 '[^[:space:]]')
  # A leading and a trailing space, so that " app=cart " is found in the list.
  PLABELS=" $(k -n "$NS" get pod "$FIRSTPOD" -o go-template='{{range $k, $v := .metadata.labels}}{{$k}}={{$v}} {{end}}' 2>/dev/null) "
  MISMATCH=""
  for entry in $SEL; do
    case "$PLABELS" in
      *" $entry "*) ok "the Service selector '$entry' matches the pods' labels" ;;
      *) bad "the Service selector '$entry' matches the pods' labels (the pods carry:$PLABELS)"; MISMATCH="$MISMATCH $entry" ;;
    esac
  done
fi

# ---------------------------------------------------------------------------
# the Service has endpoints
# ---------------------------------------------------------------------------
EP=0
i=0
while [ "$i" -lt 15 ]; do
  EP=$(k -n "$NS" get endpoints "$SVC" -o jsonpath='{range .subsets[*].addresses[*]}{.ip}{"\n"}{end}' 2>/dev/null | grep -c '[0-9]' || true)
  if [ "${EP:-0}" -ge 2 ] 2>/dev/null; then break; fi
  # Newer clusters keep the addresses in EndpointSlices.
  if [ "${EP:-0}" -lt 2 ] 2>/dev/null; then
    EP=$(k -n "$NS" get endpointslices -l "kubernetes.io/service-name=$SVC" \
          -o jsonpath='{range .items[*].endpoints[*].addresses[*]}{.ip}{"\n"}{end}' 2>/dev/null | grep -c '[0-9]' || true)
    if [ "${EP:-0}" -ge 2 ] 2>/dev/null; then break; fi
  fi
  sleep 2
  i=$((i+1))
done
if [ "${EP:-0}" -ge 2 ] 2>/dev/null; then
  ok "the Service has endpoint addresses ($EP)"
else
  bad "the Service has endpoint addresses (got ${EP:-0}, want at least 2)"
fi

# ---------------------------------------------------------------------------
# the Deployment is untouched
# ---------------------------------------------------------------------------
READY=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
eq "the Deployment $DEP still has 2 ready replicas" "$READY" "2"

note "A Service whose selector matches nothing is a perfectly valid object: it"
note "simply has no endpoints, and nothing errors. The mismatch between what the"
note "Service selects on and what the pods carry is the whole failure."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}x15 PASSED${X}"; else echo -e "${R}x15 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
