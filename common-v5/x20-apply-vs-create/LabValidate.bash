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

NS=traps
SVC=svc
DEP=web
LABDIR=/tmp/cka-lab

echo "== x20: An object that was never applied =="

# ---- the Deployment is not part of the question ----
exists "Deployment $DEP exists in namespace $NS" -n "$NS" deploy "$DEP"
ORIG=$(cat "$LABDIR/x20.dep.uid" 2>/dev/null || true)
NOW=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.metadata.uid}' 2>/dev/null)
if [ -z "$ORIG" ]; then
  bad "the Deployment is untouched (no UID was recorded at setup)"
elif [ "$ORIG" = "$NOW" ]; then
  ok "the Deployment is untouched (its UID is unchanged)"
else
  bad "the Deployment is untouched (its UID changed)"
fi

if ! exists "Service $SVC exists in namespace $NS" -n "$NS" svc "$SVC"; then
  echo; echo -e "${R}x20 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the live Service ----
LPORT=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
LTPORT=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null | tr -d '"')
LPORTS=$(k -n "$NS" get svc "$SVC" -o go-template='{{len .spec.ports}}' 2>/dev/null)

eq "the live Service exposes exactly one port" "${LPORTS:-0}" "1"
eq "the live Service's port is 8080" "${LPORT:-}" "8080"
eq "the live Service's targetPort is 80" "${LTPORT:-}" "80"

# ---- and it was APPLIED, not only patched ----
# The annotation is the record of what was applied. If the Service carries
# one, the JSON inside it is what kubectl last applied - and it has to agree
# with the live object.
ANN=$(k -n "$NS" get svc "$SVC" \
        -o go-template='{{index .metadata.annotations "kubectl.kubernetes.io/last-applied-configuration"}}' 2>/dev/null)
if [ -z "$ANN" ]; then
  bad "the live Service carries the last-applied-configuration annotation (it does not)"
else
  ok "the live Service carries the last-applied-configuration annotation"
  printf '%s' "$ANN" > "$LABDIR/x20.ann.json"
  APORTS=$(k apply --dry-run=client -f "$LABDIR/x20.ann.json" -o go-template='{{len .spec.ports}}' 2>/dev/null)
  APORT=$(k apply --dry-run=client -f "$LABDIR/x20.ann.json" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
  ATP=$(k apply --dry-run=client -f "$LABDIR/x20.ann.json" -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null | tr -d '"')
  ASEL=$(k apply --dry-run=client -f "$LABDIR/x20.ann.json" -o go-template='{{range $k, $v := .spec.selector}}{{$k}}={{$v}} {{end}}' 2>/dev/null)

  if [ "${APORTS:-0}" = "${LPORTS:-0}" ] && [ "${APORT:-}" = "${LPORT:-}" ] && [ "${ATP:-}" = "${LTPORT:-}" ]; then
    ok "the last-applied configuration matches the live Service's ports"
  else
    bad "the last-applied configuration matches the live Service's ports (applied: ${APORTS:-?} port(s), port ${APORT:-?}, targetPort ${ATP:-?}; live: ${LPORTS:-?} port(s), port ${LPORT:-?}, targetPort ${LTPORT:-?})"
  fi

  LSEL=$(k -n "$NS" get svc "$SVC" -o go-template='{{range $k, $v := .spec.selector}}{{$k}}={{$v}} {{end}}' 2>/dev/null)
  if [ "$ASEL" = "$LSEL" ]; then
    ok "the last-applied configuration matches the live Service's selector"
  else
    bad "the last-applied configuration matches the live Service's selector (applied: '${ASEL:-<none>}', live: '${LSEL:-<none>}')"
  fi
fi

# ---- the selector still matches the pods ----
LSEL=$(k -n "$NS" get svc "$SVC" -o go-template='{{range $k, $v := .spec.selector}}{{$k}}={{$v}} {{end}}' 2>/dev/null)
SELFOUND=0
for entry in $LSEL; do
  KEY=${entry%%=*}
  VAL=${entry#*=}
  SELFOUND=1
  PODLABEL=$(k -n "$NS" get deploy "$DEP" -o jsonpath="{.spec.template.metadata.labels.$KEY}" 2>/dev/null)
  eq "the Service selector '$KEY=$VAL' matches the pods' label" "$PODLABEL" "$VAL"
done
if [ "$SELFOUND" = "0" ]; then
  bad "the Service has a selector (it has none)"
else
  ok "the Service has a selector"
fi

# ---- and it really resolves to the pods ----
EP=0
for i in $(seq 1 15); do
  EP=$(k -n "$NS" get endpoints "$SVC" \
        -o jsonpath='{range .subsets[*].addresses[*]}{.ip}{"\n"}{end}' 2>/dev/null | grep -c '[0-9]' || true)
  if [ "${EP:-0}" -ge 1 ] 2>/dev/null; then break; fi
  sleep 2
done
if [ "${EP:-0}" -ge 1 ] 2>/dev/null; then
  ok "the Service has at least one endpoint ($EP endpoint addresses)"
else
  bad "the Service has at least one endpoint (got $EP endpoint addresses)"
fi

# ---- the manifest that was applied ----
FILE=""
for p in /root/svc.yaml "$HOME/svc.yaml" ./svc.yaml "$LABDIR/svc.yaml"; do
  if [ -n "$p" ] && [ -f "$p" ]; then FILE="$p"; break; fi
done
if [ -z "$FILE" ]; then
  bad "the manifest /root/svc.yaml exists (it was not found)"
else
  ok "the manifest exists ($FILE)"
  FNAME=$(k apply --dry-run=client -f "$FILE" -o jsonpath='{.metadata.name}' 2>/dev/null)
  FNS=$(k apply --dry-run=client -f "$FILE" -o jsonpath='{.metadata.namespace}' 2>/dev/null)
  FPORT=$(k apply --dry-run=client -f "$FILE" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
  FTP=$(k apply --dry-run=client -f "$FILE" -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null | tr -d '"')
  eq "the manifest defines the Service '$SVC'" "${FNAME:-}" "$SVC"
  if [ "$FNS" = "$NS" ] || [ -z "$FNS" ]; then
    ok "the manifest is for namespace $NS"
  else
    bad "the manifest is for namespace $NS (got '${FNS:-<none>}')"
  fi
  eq "the manifest's port is 8080" "${FPORT:-}" "8080"
  eq "the manifest's targetPort is 80" "${FTP:-}" "80"
fi

note "kubectl apply is a three-way merge: the manifest you apply, the"
note "configuration it last applied, and the live object. Without a"
note "last-applied configuration there is nothing to diff against."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}x20 PASSED${X}"; else echo -e "${R}x20 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
