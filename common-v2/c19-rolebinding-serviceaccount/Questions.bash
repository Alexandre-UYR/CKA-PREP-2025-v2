# Question: A Role bound to a ServiceAccount
#
# Task:
# In namespace `audit` there is a ServiceAccount named `auditor`.
#
#   1. Create a Role named `pod-reader` in namespace `audit` that allows
#      `get`, `list` and `watch` on pods, and nothing else.
#
#   2. Create a RoleBinding named `pod-reader-binding` in namespace `audit`
#      that binds that Role to the ServiceAccount `auditor` in the same
#      namespace.
#
#   3. Prove it:
#      kubectl auth can-i list pods --as=system:serviceaccount:audit:auditor -n audit
#      must answer "yes",
#      kubectl auth can-i delete pods --as=system:serviceaccount:audit:auditor -n audit
#      must answer "no", and
#      kubectl auth can-i list pods --as=system:serviceaccount:audit:auditor -n default
#      must answer "no" - the same check in a different namespace.
