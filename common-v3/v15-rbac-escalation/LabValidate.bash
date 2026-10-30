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

# `kubectl auth can-i` exits non-zero when the answer is "no", so the output
# is piped and the exit code is thrown away.
cani(){ kubectl auth can-i "$@" 2>/dev/null | tail -n 1 | tr -d '[:space:]'; }
# does the space separated list in $1 contain the exact word in $2?
list_has(){ case " $1 " in *" $2 "*) return 0;; *) return 1;; esac; }

NS=esc
SA=helper
ROLE=helper-role

echo "== v15: The permission that lets you grant yourself permissions =="

if ! exists "Role $ROLE exists in namespace $NS" -n "$NS" role "$ROLE"; then
  echo; echo -e "${R}v15 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- walk the rules of the Role, one at a time ----
PODS_GET=0
PODS_LIST=0
HAS_ESC=0
HAS_BIND=0
HAS_WILD=0
RULES_SEEN=""
i=0
while [ "$i" -lt 25 ]; do
  VERBS=$(k -n "$NS" get role "$ROLE" -o jsonpath="{.rules[$i].verbs}" 2>/dev/null)
  [ -z "$VERBS" ] && break
  RES=$(k -n "$NS" get role "$ROLE" -o jsonpath="{.rules[$i].resources}" 2>/dev/null)
  RULES_SEEN="$RULES_SEEN rule[$i]: $RES -> $VERBS;"

  list_has "$VERBS" "escalate" && HAS_ESC=1
  list_has "$VERBS" "bind" && HAS_BIND=1
  # The verb list is matched word by word: a "*" in the pattern would
  # otherwise be read as a glob and match anything.
  if printf '%s\n' "$VERBS" | tr ' ' '\n' | grep -qx '\*'; then HAS_WILD=1; fi

  if list_has "$RES" "pods"; then
    list_has "$VERBS" "get" && PODS_GET=1
    list_has "$VERBS" "list" && PODS_LIST=1
  fi

  i=$((i+1))
done

note "the rules the validator found:${RULES_SEEN:- none}"

if [ "$PODS_GET" -eq 1 ]; then
  ok "the Role still grants get on pods"
else
  bad "the Role still grants get on pods (no rule gives get on pods)"
fi

if [ "$PODS_LIST" -eq 1 ]; then
  ok "the Role still grants list on pods"
else
  bad "the Role still grants list on pods (no rule gives list on pods)"
fi

if [ "$HAS_ESC" -eq 1 ]; then
  bad "the Role no longer grants escalate (some rule still has the escalate verb)"
else
  ok "the Role no longer grants escalate"
fi

if [ "$HAS_BIND" -eq 1 ]; then
  bad "the Role no longer grants bind (some rule still has the bind verb)"
else
  ok "the Role no longer grants bind"
fi

if [ "$HAS_WILD" -eq 1 ]; then
  bad "no rule uses a wildcard verb (some rule still has the * verb)"
else
  ok "no rule uses a wildcard verb"
fi

# ---- prove it with the same tool the task asked for ----
ESC=$(cani escalate roles --as=system:serviceaccount:$NS:$SA -n "$NS" || true)
eq "can-i escalate roles answers no" "$ESC" "no"

BIND=$(cani bind roles --as=system:serviceaccount:$NS:$SA -n "$NS" || true)
eq "can-i bind roles answers no" "$BIND" "no"

CREATE=$(cani create pods --as=system:serviceaccount:$NS:$SA -n "$NS" || true)
eq "can-i create pods answers no" "$CREATE" "no"

LIST=$(cani list pods --as=system:serviceaccount:$NS:$SA -n "$NS" || true)
eq "can-i list pods still answers yes" "$LIST" "yes"

note "escalate lets the holder write a Role granting permissions it does not"
note "hold itself; bind lets it attach a Role to a ServiceAccount it does not"
note "control. Neither belongs in a read-only ServiceAccount's Role."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}v15 PASSED${X}"; else echo -e "${R}v15 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
