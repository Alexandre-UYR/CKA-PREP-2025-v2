# 1. Prove the hole.
kubectl auth can-i escalate roles --as=system:serviceaccount:esc:helper -n esc
# yes

kubectl auth can-i bind roles --as=system:serviceaccount:esc:helper -n esc
# yes

kubectl auth can-i list pods --as=system:serviceaccount:esc:helper -n esc
# yes

# `kubectl auth can-i` exits non-zero when the answer is "no", so read the
# output rather than the exit status:
#   kubectl auth can-i escalate roles --as=system:serviceaccount:esc:helper -n esc \
#     | tail -n 1 | tr -d '[:space:]'

# 2. Look at the Role.
kubectl -n esc get role helper-role -o yaml
# rules:
# - apiGroups: [""]
#   resources: ["pods"]
#   verbs: ["get", "list"]
# - apiGroups: ["rbac.authorization.k8s.io"]
#   resources: ["roles"]
#   verbs: ["escalate", "bind"]

# 3. Take the escalation away. The second rule is the one that has to go;
#    the first one is the access the ServiceAccount is entitled to.
kubectl -n esc patch role helper-role --type=json \
  -p='[{"op":"remove","path":"/rules/1"}]'

# Recreating the Role in one piece works just as well:
#   kubectl -n esc delete role helper-role
#   kubectl -n esc create role helper-role --verb=get --verb=list --resource=pods
# (the RoleBinding is untouched by either route, because it refers to the
# Role by name)

# 4. Prove the fix.
kubectl -n esc get role helper-role -o yaml
# rules:
# - apiGroups: [""]
#   resources: ["pods"]
#   verbs: ["get", "list"]

kubectl auth can-i escalate roles --as=system:serviceaccount:esc:helper -n esc
# no

kubectl auth can-i bind roles --as=system:serviceaccount:esc:helper -n esc
# no

kubectl auth can-i create pods --as=system:serviceaccount:esc:helper -n esc
# no

kubectl auth can-i list pods --as=system:serviceaccount:esc:helper -n esc
# yes

# The read access is still there and the escalation is not. What the two
# verbs were worth: escalate lets its holder write a Role granting
# permissions it does not hold itself, and bind lets it attach a Role to a
# ServiceAccount it does not control. Neither belongs in a Role that is
# only supposed to let someone read pods.
