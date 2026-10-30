# Question: Which machine is the busiest
#
# The cluster reports no metrics, so `kubectl top` does not work. In the
# `metrics` namespace there are three Deployments: `hog`, which is greedy with
# memory, and `calm-one` and `calm-two`, which sleep.
#
# Task:
# 1. Install a metrics server, so that `kubectl top` works.
# 2. Find the node with the highest memory usage and write its name to
#    /root/busiest-node.txt.
# 3. Find the Pod in the `metrics` namespace using the most memory and write
#    `namespace/podname` to /root/hottest-pod.txt.
#
# Done means: `kubectl top` works, and both files hold the answer.
