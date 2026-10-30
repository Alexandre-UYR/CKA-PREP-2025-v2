# Question: Place a Pod on a specific node
#
# Task:
# In the scheduling namespace, exactly one node carries the label
# workload=general.
#
# 1. Create a Pod named pinned that runs on that node, pinning it directly
#    with the nodeName field.
# 2. Create a second Pod named selected that lands on that same node, but
#    using a nodeSelector instead of nodeName.
#
# Both Pods must be Running.
