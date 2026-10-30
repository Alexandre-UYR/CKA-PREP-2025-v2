# Question: Three ways of asking to be put somewhere
#
# The namespace `place` is empty. The cluster has a worker node labelled
# `workload=general` and a control-plane node.
#
# Task:
# Place three Pods in the `place` namespace, all of them on the node labelled
# `workload=general`:
#
#   `pinned`   - using `nodeName`, which names the node outright;
#   `selected` - using a `nodeSelector`;
#   `together` - using pod affinity, so that it lands on the same node as
#                `selected`.
#
# All three must be Running on that node. Use the image nginx:1.25.
#
# `selected` must carry the label `app=selected`, because `together`'s
# affinity refers to it.
#
# Find the node by its label. Do not write a node name into the manifest.
