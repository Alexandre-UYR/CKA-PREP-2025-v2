# Question: Which log belongs to which component
#
# On this control-plane node, five different components are writing logs, and
# they do not all write them in the same place.
#
# Task:
# 1. Find the log files of the control plane components. Write the paths of
#    the API server log, the scheduler log, the controller manager log, the
#    kubelet log and the kube-proxy log to /root/control-plane-logs.txt - one
#    path per line, in that order.
# 2. Answer a second question: which of those components is responsible for
#    making scheduling decisions? Write its name to /root/scheduler-component.txt.
#
# Every path you write has to be a file that exists on this node.
