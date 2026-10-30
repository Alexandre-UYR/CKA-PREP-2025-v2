#!/bin/bash
set -e

# v15 - The permission that lets you grant yourself permissions
#
# The pre-state is a namespace in which a read-only ServiceAccount has been
# handed `escalate` and `bind` on roles. That is the classic privilege
# escalation hole: escalate lets the holder write a Role granting itself
# anything in the namespace, and bind lets it hand that Role to anyone else
# there.
#
# The namespace is recreated on every run, so the setup is idempotent and the
# starting state is always the same.

NS=esc
SA=helper
ROLE=helper-role
BINDING=helper-binding

kubectl delete namespace "$NS" --ignore-not-found --wait=true --timeout=120s >/dev/null 2>&1 || true
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $SA
  namespace: $NS
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: $ROLE
  namespace: $NS
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list"]
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["roles"]
    verbs: ["escalate", "bind"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: $BINDING
  namespace: $NS
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: $ROLE
subjects:
  - kind: ServiceAccount
    name: $SA
    namespace: $NS
EOF

# Show that the hole is open. `kubectl auth can-i` exits non-zero when the
# answer is "no", so the output is piped and the exit code is ignored.
cani(){ kubectl auth can-i "$@" 2>/dev/null | tail -n 1 | tr -d '[:space:]'; }

ESC=$(cani escalate roles --as=system:serviceaccount:$NS:$SA -n "$NS" || true)
BIND=$(cani bind roles --as=system:serviceaccount:$NS:$SA -n "$NS" || true)
LIST=$(cani list pods --as=system:serviceaccount:$NS:$SA -n "$NS" || true)
CREATE=$(cani create pods --as=system:serviceaccount:$NS:$SA -n "$NS" || true)

echo "✅ v15 environment ready"
echo "   - namespace: $NS"
echo "   - ServiceAccount: $SA"
echo "   - Role: $ROLE"
echo "   -   pods  : get, list"
echo "   -   roles : escalate, bind   <-- the hole"
echo "   - RoleBinding: $BINDING ($ROLE -> $SA)"
echo "   - can-i escalate roles : ${ESC:-<unknown>}"
echo "   - can-i bind roles     : ${BIND:-<unknown>}"
echo "   - can-i list pods      : ${LIST:-<unknown>}"
echo "   - can-i create pods    : ${CREATE:-<unknown>}"
echo "   - Task: take the escalation away, and keep the read access"

if [ "$ESC" != "yes" ]; then
  echo "   ⚠️  The ServiceAccount does not answer yes to 'escalate roles'." >&2
  echo "      The pre-state is not what the task describes. Check:" >&2
  echo "      kubectl -n $NS get role $ROLE -o yaml" >&2
fi
