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

NS=ops
SA=builder
CR=workload-creator
CRB=builder-workloads
AS_USER="system:serviceaccount:${NS}:${SA}"

echo "== c18: A ClusterRole that grants exactly one verb =="

# ---- the ClusterRole ----
if ! exists "ClusterRole $CR exists" clusterrole "$CR"; then
  echo; echo -e "${R}c18 FAILED ($FAILS checks)${X}"; exit 1
fi

# The rules, read as one flat list each. The go-template wraps every value in
# parentheses so that a value can never be confused with its neighbours.
VERBS=$(k get clusterrole "$CR" -o go-template='{{range .rules}}{{range .verbs}}({{.}}){{end}}{{end}}' 2>/dev/null)
RESOURCES=$(k get clusterrole "$CR" -o go-template='{{range .rules}}{{range .resources}}({{.}}){{end}}{{end}}' 2>/dev/null)
APIGROUPS=$(k get clusterrole "$CR" -o go-template='{{range .rules}}{{range .apiGroups}}({{if .}}{{.}}{{else}}CORE{{end}}){{end}}{{end}}' 2>/dev/null)

VSET=$(printf '%s' "$VERBS" | tr '()' '\n' | sed '/^$/d' | sort -u | tr '\n' ' ' | sed 's/ *$//')
RSET=$(printf '%s' "$RESOURCES" | tr '()' '\n' | sed '/^$/d' | sort -u | tr '\n' ' ' | sed 's/ *$//')
ASET=$(printf '%s' "$APIGROUPS" | tr '()' '\n' | sed '/^$/d' | sort -u | tr '\n' ' ' | sed 's/ *$//')

eq "the rules grant exactly one verb, and it is create" "$VSET" "create"
eq "the rules name exactly deployments, statefulsets and daemonsets" "$RSET" "daemonsets deployments statefulsets"
eq "the rules apply to exactly the apps apiGroup" "$ASET" "apps"

# The two "no wildcard" constraints, stated separately from the exact sets.
case "$VSET" in *'*'*) bad "the rules grant no wildcard verb (want no '*' anywhere in the verb list, got '$VSET')";; *) ok "the rules grant no wildcard verb";; esac
case "$RSET" in *'*'*) bad "the rules name no wildcard resource (want no '*' anywhere in the resource list, got '$RSET')";; *) ok "the rules name no wildcard resource";; esac

# ---- the ClusterRoleBinding ----
if ! exists "ClusterRoleBinding $CRB exists" clusterrolebinding "$CRB"; then
  echo; echo -e "${R}c18 FAILED ($FAILS checks)${X}"; exit 1
fi

eq "the binding's roleRef names the ClusterRole $CR" \
   "$(k get clusterrolebinding "$CRB" -o jsonpath='{.roleRef.name}' 2>/dev/null)" "$CR"
eq "the binding's roleRef kind is ClusterRole" \
   "$(k get clusterrolebinding "$CRB" -o jsonpath='{.roleRef.kind}' 2>/dev/null)" "ClusterRole"

SUBJECTS=$(k get clusterrolebinding "$CRB" -o go-template='{{range .subjects}}{{.kind}}/{{.name}}/{{.namespace}}{{"\n"}}{{end}}' 2>/dev/null)
has "the binding subjects include ServiceAccount $SA in namespace $NS" "$SUBJECTS" "ServiceAccount/${SA}/${NS}"

# ---- the proof ----
YES=$(k auth can-i create deployments --as="$AS_USER" 2>/dev/null | tail -n 1 | tr -d '[:space:]' || true)
eq "kubectl auth can-i create deployments --as=$AS_USER answers yes" "$YES" "yes"

NO=$(k auth can-i delete deployments --as="$AS_USER" 2>/dev/null | tail -n 1 | tr -d '[:space:]' || true)
eq "kubectl auth can-i delete deployments --as=$AS_USER answers no" "$NO" "no"

note "A ClusterRole is cluster-scoped, so it needs a ClusterRoleBinding to reach"
note "a namespaced ServiceAccount. A plain RoleBinding cannot reference a"
note "ClusterRole at all - the API server rejects it."
note "The can-i probe is the real proof. The object can look right and still not"
note "grant what you think, because the apiGroup has to match too: apps, not"
note "the core group."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c18 PASSED${X}"; else echo -e "${R}c18 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
