# Question: Cluster DNS has stopped working
#
# Task:
# Pods in the `dns` namespace cannot resolve `kubernetes.default.svc.cluster.local`.
#
# Diagnose the cause and fix the cluster's DNS so that name resolution works
# again, without restarting the nodes.
#
# Verify with a pod that resolves `kubernetes.default.svc.cluster.local`:
#
#   kubectl -n dns run dnsprobe --rm -i --restart=Never --image=busybox:1.36 -- \
#     nslookup kubernetes.default.svc.cluster.local
#
# Clean the probe pod up when you are done.
