# The Role. Pods live in the core API group, so apiGroups is the empty string.
cat <<'EOF' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: audit
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
EOF

# The RoleBinding. Both objects live in the audit namespace, and the subject
# has to name the namespace explicitly.
cat <<'EOF' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader-binding
  namespace: audit
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: pod-reader
subjects:
  - kind: ServiceAccount
    name: auditor
    namespace: audit
EOF

# The proof.
kubectl auth can-i list pods --as=system:serviceaccount:audit:auditor -n audit
# yes

kubectl auth can-i delete pods --as=system:serviceaccount:audit:auditor -n audit
# no

# The same check in another namespace - the grant stops at the namespace edge.
kubectl auth can-i list pods --as=system:serviceaccount:audit:auditor -n default
# no

# What the API server thinks the rules are.
kubectl -n audit get role pod-reader -o jsonpath='{.rules[*].verbs[*]}'
# get list watch
kubectl -n audit get role pod-reader -o jsonpath='{.rules[*].resources[*]}'
# pods
kubectl -n audit get role pod-reader -o jsonpath='{.rules[*].apiGroups[*]}'
# (an empty line: the core group is the empty string)

# To actually use the grant, run a pod as the ServiceAccount:
#
#   kubectl -n audit run audit-check --image=nginx:alpine \
#     --overrides='{"spec":{"serviceAccountName":"auditor","containers":[{"name":"audit-check","image":"nginx:alpine","command":["sleep","3600"],"stdin":true,"tty":true}]}}'
#   kubectl -n audit exec -it audit-check -- kubectl get pods
#
# The bind only takes effect for pods that use the ServiceAccount.
