# Question: Bring the nodes back
#
# Two nodes in the cluster are out of service. One of them is marked
# unschedulable, so that no new pods land on it. The other carries the taint
# dedicated=payments:NoSchedule.
#
# Task:
# 1. Put both right. The cordoned node must be schedulable again, and the
#    taint must be gone from the other.
# 2. Label the node that carried the taint with `Status=VIP`.
# 3. Prove the label is usable as a selector:
#
#      kubectl get nodes -l Status=VIP
#
#    It must return exactly that one node.
#
# When you are done, no node in the cluster may carry the
# dedicated=payments taint.
