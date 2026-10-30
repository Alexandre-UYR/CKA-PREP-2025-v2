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

NS=adopt
DEP=web
NEW=web-adopted

echo "== v18: Take the pods over from their old owner =="

if ! exists "ReplicaSet $NEW exists in namespace $NS" -n "$NS" rs "$NEW"; then
  echo; echo -e "${R}v18 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the new ReplicaSet ----------------------------------------------------

REPLICAS=$(k -n "$NS" get rs "$NEW" -o jsonpath='{.spec.replicas}' 2>/dev/null)
eq "the ReplicaSet $NEW asks for 2 replicas" "$REPLICAS" "2"

SELJSON=$(k -n "$NS" get rs "$NEW" -o jsonpath='{.spec.selector}' 2>/dev/null)
nonempty "the ReplicaSet $NEW has a selector" "$SELJSON"

APP=$(k -n "$NS" get rs "$NEW" -o jsonpath='{.spec.selector.matchLabels.app}' 2>/dev/null)
if [ "$APP" = "web" ]; then
  ok "the selector matches app=web"
elif [ -n "$APP" ]; then
  bad "the selector matches app=web (its matchLabels.app is '$APP')"
elif printf '%s' "$SELJSON" | grep -q 'web'; then
  ok "the selector matches app=web (matchExpressions)"
else
  bad "the selector matches app=web (the selector is '$SELJSON')"
fi

# ---- the pods ---------------------------------------------------------------

PODS=$(k -n "$NS" get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)

RUNNING=0
OWNED=0
OWNED_KIND=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  PH=$(k -n "$NS" get pod "$p" -o jsonpath='{.status.phase}' 2>/dev/null)
  OWNER=$(k -n "$NS" get pod "$p" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null)
  KIND=$(k -n "$NS" get pod "$p" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null)
  [ "$PH" = "Running" ] && RUNNING=$((RUNNING+1))
  if [ "$OWNER" = "$NEW" ]; then
    OWNED=$((OWNED+1))
    [ "$KIND" = "ReplicaSet" ] && OWNED_KIND=$((OWNED_KIND+1))
  fi
done <<EOF
$PODS
EOF

eq "there are 2 Running pods in the namespace" "$RUNNING" "2"
eq "both Running pods are controlled by $NEW" "$OWNED" "2"
eq "the ownerReference of both pods says kind ReplicaSet" "$OWNED_KIND" "2"

# ---- the old ReplicaSet has let go ------------------------------------------

OLD=$(k -n "$NS" get rs -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
        | grep "^${DEP}-" | grep -v "^${NEW}$" || true)

if [ -z "$OLD" ]; then
  ok "the old ReplicaSet is gone"
else
  for o in $OLD; do
    [ -n "$o" ] || continue
    r=$(k -n "$NS" get rs "$o" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "")
    if [ "$r" = "0" ]; then
      ok "the old ReplicaSet $o no longer owns the pods (it is scaled to 0)"
    elif [ -z "$r" ]; then
      ok "the old ReplicaSet $o is gone"
    else
      bad "the old ReplicaSet $o no longer owns the pods (it still has $r replicas)"
    fi
  done
fi

# ---- the pods were adopted, not replaced -------------------------------------

ORIG=$(k -n "$NS" get namespace "$NS" \
        -o go-template='{{index .metadata.annotations "cka-lab/original-pods"}}' 2>/dev/null || true)

if [ -z "$ORIG" ]; then
  skip "the original pods are the same pods (the setup did not record their UIDs)"
else
  KEPT=0
  TOTALORIG=0
  OLDIFS=$IFS
  IFS=','
  for entry in $ORIG; do
    [ -n "$entry" ] || continue
    TOTALORIG=$((TOTALORIG+1))
    pname=${entry%%=*}
    puid=${entry#*=}
    cur=$(k -n "$NS" get pod "$pname" -o jsonpath='{.metadata.uid}' 2>/dev/null || true)
    [ -n "$cur" ] || continue
    [ "$cur" = "$puid" ] || continue
    owner=$(k -n "$NS" get pod "$pname" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null || true)
    if [ "$owner" = "$NEW" ]; then
      KEPT=$((KEPT+1))
    fi
  done
  IFS=$OLDIFS
  eq "both original pods are still the same pods, adopted by $NEW" "$KEPT" "$TOTALORIG"
fi

note "A ReplicaSet adopts a pod only when the pod's labels match its selector"
note "AND the pod has no controller - so the old owner has to let go first."
note "The Deployment and a ReplicaSet must not fight over the same pods,"
note "which is why a Deployment's own ReplicaSet carries a pod-template hash."
note "An adopted pod keeps its old name (web-<hash>-xxxxx); only its owner"
note "changes. A pod that was replaced has a new name AND a new UID."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}v18 PASSED${X}"; else echo -e "${R}v18 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
