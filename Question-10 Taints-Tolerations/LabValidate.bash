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

echo "== Q10 Taints & Tolerations =="

# ---- task 1: the taint ----
# kubectl's jsonpath prints taints as [map[key:PERMISSION value:granted effect:NoSchedule]]
TAINTLINE=$(k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.taints}{"\n"}{end}' 2>/dev/null \
  | grep 'key:PERMISSION' | grep 'value:granted' | grep 'effect:NoSchedule' | head -1)
TARGET=$(printf '%s' "$TAINTLINE" | awk '{print $1}')

if [ -z "$TARGET" ]; then
  bad "a node carries the taint PERMISSION=granted:NoSchedule (found none)"
  echo -e "      HINT  kubectl taint nodes <node> PERMISSION=granted:NoSchedule"
  echo; echo -e "${R}Q10 FAILED ($FAILS checks)${X}"; exit 1
fi
ok "the taint PERMISSION=granted:NoSchedule is on node '$TARGET'"

# ---- task 2: a pod that tolerates it, running on that node ----
# namespace|name|nodeName|phase|ownerKind
PODLINE=$(k get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"|"}{.spec.nodeName}{"|"}{.status.phase}{"|"}{.metadata.ownerReferences[0].kind}{"\n"}{end}' 2>/dev/null \
  | awk -F'|' -v n="$TARGET" '$1!="kube-system" && $3==n && $4=="Running" && $5!="DaemonSet" {print; exit}')

PODNS=$(printf '%s' "$PODLINE" | cut -d'|' -f1)
PODNAME=$(printf '%s' "$PODLINE" | cut -d'|' -f2)

if [ -z "$PODNAME" ]; then
  bad "a non-system pod is Running on the tainted node '$TARGET' (found none)"
  echo -e "      HINT  a DaemonSet pod does not count - DaemonSets tolerate every taint by design"
  echo; echo -e "${R}Q10 FAILED ($FAILS checks)${X}"; exit 1
fi
ok "pod $PODNS/$PODNAME is Running on the tainted node"

TOLKEY=$(k -n "$PODNS" get pod "$PODNAME" -o jsonpath='{.spec.tolerations[*].key}' 2>/dev/null)
TOLEFF=$(k -n "$PODNS" get pod "$PODNAME" -o jsonpath='{.spec.tolerations[*].effect}' 2>/dev/null)
TOLEVAL=$(k -n "$PODNS" get pod "$PODNAME" -o jsonpath='{.spec.tolerations[*].operator}' 2>/dev/null)
TOLVAL=$(k -n "$PODNS" get pod "$PODNAME" -o jsonpath='{.spec.tolerations[*].value}' 2>/dev/null)

has "the pod tolerates the key PERMISSION" " $TOLKEY " " PERMISSION "
has "the toleration has effect NoSchedule" " $TOLEFF " " NoSchedule "
case " $TOLVAL " in
  *" granted "*) ok "the toleration matches the value granted";;
  *) note "the pod's toleration list carries no value 'granted' (an Exists toleration tolerates any value)";
esac

# ---- the other half of the task: ordinary pods must stay away ----
OFFENDER=$(k get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"|"}{.spec.nodeName}{"\n"}{end}' 2>/dev/null \
  | awk -F'|' -v n="$TARGET" '$1!="kube-system" && $3==n && $2!="'"$PODNAME"'" {print $1"/"$2; exit}')
if [ -n "$OFFENDER" ]; then
  bad "pod $OFFENDER also runs on the tainted node without tolerating it"
else
  ok "no other ordinary pod was scheduled onto the tainted node"
fi

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}Q10 PASSED${X}"; else echo -e "${R}Q10 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
