# Question: One pod per node, including the control plane
#
# The `ds` namespace is empty, but the cluster is not. Its control-plane node
# is tainted, so anything you deploy there without a toleration is skipped
# without a word - and one of the nodes carries the label monitoring=yes,
# which looks like a reason to write a nodeSelector.
#
# Task:
# 1. Deploy a DaemonSet `agent` in namespace `ds` that runs on EVERY node in
#    the cluster - including the control-plane node, which is tainted and
#    would otherwise be skipped.
# 2. The DaemonSet must use `hostNetwork: true`, so the agent can report on
#    the node it runs on.
# 3. It must tolerate the control-plane taint. A toleration on its own is not
#    enough: the pod still has to fit on the node.
# 4. Every pod of the DaemonSet must be Ready.
#
# Check `kubectl -n ds get ds agent`: DESIRED must equal the number of nodes
# in the cluster, and READY must equal DESIRED.
