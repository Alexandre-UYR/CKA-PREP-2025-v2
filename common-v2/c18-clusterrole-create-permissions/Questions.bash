# Question: A ClusterRole that grants exactly one verb
#
# Task:
# In namespace `ops` there is a ServiceAccount named `builder`.
#
#   1. Create a ClusterRole named `workload-creator` that allows `create` on
#      deployments, statefulsets and daemonsets in the `apps` API group, and
#      NOTHING else - no other verbs, no wildcard resources.
#
#   2. Bind it to the ServiceAccount `builder` in namespace `ops` with a
#      ClusterRoleBinding named `builder-workloads`.
#
#   3. Prove it:
#      kubectl auth can-i create deployments --as=system:serviceaccount:ops:builder
#      must answer "yes", and
#      kubectl auth can-i delete deployments --as=system:serviceaccount:ops:builder
#      must answer "no".
