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

NS=audit
SA=auditor
ROLE=pod-reader
RB=pod-reader-binding
AS_USER="system:serviceaccount:${NS}:${SA}"

echo "== c19: A Role bound to a ServiceAccount =="

# ---- the Role ----
if ! exists "Role $ROLE exists in namespace $NS" -n "$NS" role "$ROLE"; then
  echo; echo -e "${R}c19 FAILED ($FAILS checks)${X}"; exit 1
fi

# The rules, read as one flat list each. The go-template wraps every value in
# parentheses so that a value can never be confused with its neighbours, and
# prints the empty apiGroup (the core group) as CORE.
VERBS=$(k -n "$NS" get role "$ROLE" -o go-template='{{range .rules}}{{range .verbs}}({{.}}){{end}}{{end}}' 2>/dev/null)
RESOURCES=$(k -n "$NS" get role "$ROLE" -o go-template='{{range .rules}}{{range .resources}}({{.}}){{end}}{{end}}' 2>/dev/null)
APIGROUPS=$(k -n "$NS" get role "$ROLE" -o go-template='{{range .rules}}{{range .apiGroups}}({{if .}}{{.}}{{else}}CORE{{end}}){{end}}{{end}}' 2>/dev/null)

VSET=$(printf '%s' "$VERBS" | tr '()' '\n' | sed '/^$/d' | sort -u | tr '\n' ' ' | sed 's/ *$//')
RSET=$(printf '%s' "$RESOURCES" | tr '()' '\n' | sed '/^$/d' | sort -u | tr '\n' ' ' | sed 's/ *$//')
ASET=$(printf '%s' "$APIGROUPS" | tr '()' '\n' | sed '/^$/d' | sort -u | tr '\n' ' ' | sed 's/ *$//')

eq "the Role grants exactly get, list and watch" "$VSET" "get list watch"
eq "the Role names exactly the resource pods" "$RSET" "pods"
eq "the Role applies to exactly the core apiGroup" "$ASET" "CORE"

case "$VSET" in *'*'*) bad "the Role grants no wildcard verb (want no '*' in the verb list, got '$VSET')";; *) ok "the Role grants no wildcard verb";; esac
case "$RSET" in *'*'*) bad "the Role names no wildcard resource (want no '*' in the resource list, got '$RSET')";; *) ok "the Role names no wildcard resource";; esac

# ---- the RoleBinding ----
if ! exists "RoleBinding $RB exists in namespace $NS" -n "$NS" rolebinding "$RB"; then
  echo; echo -e "${R}c19 FAILED ($FAILS checks)${X}"; exit 1
fi

eq "the binding's roleRef kind is Role" \
   "$(k -n "$NS" get rolebinding "$RB" -o jsonpath='{.roleRef.kind}' 2>/dev/null)" "Role"
eq "the binding's roleRef names the Role $ROLE" \
   "$(k -n "$NS" get rolebinding "$RB" -o jsonpath='{.roleRef.name}' 2>/dev/null)" "$ROLE"

SUBJECTS=$(k -n "$NS" get rolebinding "$RB" -o go-template='{{range .subjects}}{{.kind}}/{{.name}}/{{.namespace}}{{"\n"}}{{end}}' 2>/dev/null)
has "the binding subjects include ServiceAccount $SA in namespace $NS" "$SUBJECTS" "ServiceAccount/${SA}/${NS}"

# ---- the proof ----
YES=$(k auth can-i list pods --as="$AS_USER" -n "$NS" 2>/dev/null | tail -n 1 | tr -d '[:space:]' || true)
eq "kubectl auth can-i list pods --as=$AS_USER -n $NS answers yes" "$YES" "yes"

NO=$(k auth can-i delete pods --as="$AS_USER" -n "$NS" 2>/dev/null | tail -n 1 | tr -d '[:space:]' || true)
eq "kubectl auth can-i delete pods --as=$AS_USER -n $NS answers no" "$NO" "no"

OTHER=$(k auth can-i list pods --as="$AS_USER" -n default 2>/dev/null | tail -n 1 | tr -d '[:space:]' || true)
eq "kubectl auth can-i list pods --as=$AS_USER -n default answers no" "$OTHER" "no"

note "A RoleBinding in a namespace only grants access WITHIN that namespace."
note "That is why the third probe answers no, and it is the whole point of"
note "namespaced RBAC."
note "Binding a Role to a ServiceAccount only takes effect for pods that use"
note "that ServiceAccount (via serviceAccountName). It does not change"
note "anyone's own permissions."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c19 PASSED${X}"; else echo -e "${R}c19 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
