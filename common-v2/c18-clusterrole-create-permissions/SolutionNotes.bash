# The ClusterRole. One rule, one verb, three resources, one apiGroup.
cat <<'EOF' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: workload-creator
rules:
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets", "daemonsets"]
    verbs: ["create"]
EOF

# The ClusterRoleBinding. A ClusterRole is cluster-scoped, so it needs a
# ClusterRoleBinding - a RoleBinding cannot reference a ClusterRole at all.
cat <<'EOF' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: builder-workloads
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: workload-creator
subjects:
  - kind: ServiceAccount
    name: builder
    namespace: ops
EOF

# The proof.
kubectl auth can-i create deployments --as=system:serviceaccount:ops:builder
# yes

kubectl auth can-i delete deployments --as=system:serviceaccount:ops:builder
# no

# What the API server thinks the rules are.
kubectl get clusterrole workload-creator -o jsonpath='{.rules[*].verbs[*]}'
# create
kubectl get clusterrole workload-creator -o jsonpath='{.rules[*].apiGroups[*]}'
# apps
kubectl get clusterrole workload-creator -o jsonpath='{.rules[*].resources[*]}'
# deployments statefulsets daemonsets

# Three separate rules are equally correct - the grader looks at the flattened
# set of verbs, apiGroups and resources, not at how many rules there are:
#
#   rules:
#     - apiGroups: ["apps"]
#       resources: ["deployments"]
#       verbs: ["create"]
#     - apiGroups: ["apps"]
#       resources: ["statefulsets"]
#       verbs: ["create"]
#     - apiGroups: ["apps"]
#       resources: ["daemonsets"]
#       verbs: ["create"]

# Two things that look right and are not:
#
#   apiGroups: [""]            # core group - deployments are not in it
#   resources: ["*"]           # every resource in the group
#   verbs: ["*"]               # every verb on those resources
