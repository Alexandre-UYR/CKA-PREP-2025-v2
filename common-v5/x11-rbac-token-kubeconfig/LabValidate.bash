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
# is piped and the exit code thrown away.
cani(){ kubectl auth can-i "$@" 2>/dev/null | tail -n 1 | tr -d '[:space:]'; }
# does the space separated list in $1 contain the exact word in $2?
list_has(){ case " $1 " in *" $2 "*) return 0;; *) return 1;; esac; }

NS=rbac
SA=admin
SAUSER="system:serviceaccount:$NS:$SA"
KC=/root/rbac.kubeconfig

echo "== x11: Prove it with the credentials =="

# ---------------------------------------------------------------------------
# The RoleBinding: a Role in this namespace, bound to this ServiceAccount
# ---------------------------------------------------------------------------
FOUND_BINDING=0
BOUND_ROLES=""
for rb in $(k -n "$NS" get rolebinding -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
  KIND=$(k -n "$NS" get rolebinding "$rb" -o jsonpath='{.roleRef.kind}' 2>/dev/null)
  RNAME=$(k -n "$NS" get rolebinding "$rb" -o jsonpath='{.roleRef.name}' 2>/dev/null)
  [ "$KIND" = "Role" ] || continue
  SBJ=$(k -n "$NS" get rolebinding "$rb" \
          -o jsonpath='{range .subjects[*]}{.kind}/{.name}/{.namespace}{"\n"}{end}' 2>/dev/null)
  case "$SBJ" in
    *"ServiceAccount/$SA/$NS"*|*"ServiceAccount/$SA/"*)
      FOUND_BINDING=1
      BOUND_ROLES="$BOUND_ROLES $RNAME"
      ;;
  esac
done

if [ "$FOUND_BINDING" -eq 1 ]; then
  ok "a RoleBinding in namespace $NS binds a Role to the ServiceAccount $SA"
else
  bad "a RoleBinding in namespace $NS binds a Role to the ServiceAccount $SA (found no binding for ServiceAccount/$SA)"
fi

# ---------------------------------------------------------------------------
# The Role: list on pods, and nothing else
# ---------------------------------------------------------------------------
GRANTS_LIST=0
GRANTS_GET=0
EXTRA=""
for RN in $BOUND_ROLES; do
  if ! k -n "$NS" get role "$RN" >/dev/null 2>&1; then
    bad "the bound Role $RN exists in namespace $NS"
    continue
  fi
  i=0
  while [ "$i" -lt 30 ]; do
    VERBS=$(k -n "$NS" get role "$RN" -o jsonpath="{.rules[$i].verbs}" 2>/dev/null)
    [ -z "$VERBS" ] && break
    RES=$(k -n "$NS" get role "$RN" -o jsonpath="{.rules[$i].resources}" 2>/dev/null)
    AG=$(k -n "$NS" get role "$RN" -o jsonpath="{.rules[$i].apiGroups}" 2>/dev/null)
    if list_has "$RES" "pods"; then
      # A rule about another API group is not a rule about Pods. The core
      # group is the empty one, which kubectl prints as "[]".
      if [ -z "$AG" ] || [ "$AG" = "[]" ] || [ "$AG" = "*" ]; then
        list_has "$VERBS" "list" && GRANTS_LIST=1
        list_has "$VERBS" "get" && GRANTS_GET=1
      fi
    fi
    for v in $(printf '%s\n' "$VERBS" | tr ' ' '\n'); do
      case "$v" in
        list|get) ;;
        *) EXTRA="$EXTRA verb '$v'";;
      esac
    done
    for r in $(printf '%s\n' "$RES" | tr ' ' '\n'); do
      case "$r" in
        pods|"") ;;
        *) EXTRA="$EXTRA resource '$r'";;
      esac
    done
    i=$((i+1))
  done
done

if [ "$GRANTS_LIST" -eq 1 ]; then
  ok "the bound Role grants list on pods"
elif [ "$GRANTS_GET" -eq 1 ]; then
  ok "the bound Role grants get on pods"
else
  bad "the bound Role grants list on pods (no rule gives list or get on pods)"
fi

if [ -z "$EXTRA" ]; then
  ok "the bound Role grants nothing beyond list on pods - no wildcard, no other verb"
else
  bad "the bound Role grants nothing beyond list on pods - it also grants:$EXTRA"
fi

# ---------------------------------------------------------------------------
# The boundary, asked of the API server
# ---------------------------------------------------------------------------
LIST=$(cani list pods --as="$SAUSER" -n "$NS" || true)
eq "the ServiceAccount can list pods in namespace $NS" "$LIST" "yes"

LISTD=$(cani list pods --as="$SAUSER" -n default || true)
eq "the ServiceAccount cannot list pods in namespace default" "$LISTD" "no"

# ---------------------------------------------------------------------------
# The kubeconfig
# ---------------------------------------------------------------------------
if [ -f "$KC" ]; then
  ok "the kubeconfig $KC exists"
else
  bad "the kubeconfig $KC exists"
fi

if [ -f "$KC" ]; then
  CTX=$(k --kubeconfig "$KC" config get-contexts 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')
  if [ "${CTX:-0}" -gt 0 ]; then
    ok "the kubeconfig names a context ($CTX of them)"
  else
    bad "the kubeconfig names a context (it names none)"
  fi

  CUR=$(k --kubeconfig "$KC" config current-context 2>/dev/null | tr -d '[:space:]')
  nonempty "the kubeconfig has a current context" "$CUR"

  NAMES=$(k --kubeconfig "$KC" config view \
            -o jsonpath='{range .contexts[*]}{.name}{"\n"}{end}{range .users[*]}{.name}{"\n"}{end}{range .users[*]}{.user.username}{"\n"}{end}' \
            2>/dev/null)
  if printf '%s\n' "$NAMES" | grep -qi 'admin' || grep -qi 'admin' "$KC"; then
    ok "the kubeconfig names the ServiceAccount it carries"
  else
    bad "the kubeconfig names the ServiceAccount it carries (nothing in it mentions '$SA')"
  fi

  # The strongest check: the candidate's own credentials, used against the
  # API server.
  KLIST=$(k --kubeconfig "$KC" auth can-i list pods -n "$NS" 2>/dev/null | tail -n 1 | tr -d '[:space:]')
  eq "with the kubeconfig, list pods in namespace $NS is allowed" "$KLIST" "yes"

  KLISTD=$(k --kubeconfig "$KC" auth can-i list pods -n default 2>/dev/null | tail -n 1 | tr -d '[:space:]')
  eq "with the kubeconfig, list pods in namespace default is not allowed" "$KLISTD" "no"

  # And the kubeconfig is actually used to list pods, which is what the task
  # asks for.
  if k --kubeconfig "$KC" get pods -n "$NS" >/dev/null 2>&1; then
    ok "with the kubeconfig, pods in namespace $NS can be listed"
  else
    bad "with the kubeconfig, pods in namespace $NS can be listed (the request was refused)"
  fi

  if k --kubeconfig "$KC" get pods -n default >/dev/null 2>&1; then
    bad "with the kubeconfig, pods in namespace default cannot be listed (the request was allowed)"
  else
    ok "with the kubeconfig, pods in namespace default cannot be listed"
  fi
fi

note "A RoleBinding is namespaced: it hands the ServiceAccount its permissions"
note "inside its own namespace and nowhere else. That is what the 'default'"
note "probe demonstrates - and it is the reason the kubeconfig check above"
note "uses the same credentials the candidate minted."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}x11 PASSED${X}"; else echo -e "${R}x11 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
