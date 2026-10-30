# Question: Taint and untaint
#
# Task:
# Remove the `do-not-use` taint from the node that carries it.
#
# Then make the `workload` Deployment in namespace `taints` schedulable on the
# node tainted `dedicated=payments:NoSchedule`: give the pod a toleration for
# that taint AND a placement rule (a nodeSelector on one of the node's labels,
# or a nodeAffinity) that puts it on that node.
#
# The Deployment must be patched, not re-created.
