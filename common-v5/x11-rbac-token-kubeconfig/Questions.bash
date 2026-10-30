# Question: Prove it with the credentials
#
# In the `rbac` namespace there is a ServiceAccount called `admin` and nothing
# else.
#
# Task:
# 1. Give the ServiceAccount `admin` permission to list the Pods in the `rbac`
#    namespace, and nothing else.
# 2. Generate a token for that ServiceAccount, put it in a kubeconfig of its own
#    as a new context, and use it to list the Pods in the `rbac` namespace.
# 3. Prove the boundary. The same credentials must be able to list Pods in
#    `rbac`, and must not be able to list Pods in the `default` namespace.
#
# Save the kubeconfig to /root/rbac.kubeconfig.
#
# Done means: the permission is granted and bound to the ServiceAccount, the
# kubeconfig works, and `kubectl auth can-i` with that kubeconfig answers yes
# for `rbac` and no for `default`.
