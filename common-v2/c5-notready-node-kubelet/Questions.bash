# Question: Bring a NotReady node back
#
# Task:
# One of the worker nodes has become NotReady. Find it, go to the node, and
# bring the kubelet back: it must be running again AND enabled, so it survives
# a reboot. Confirm the node reports Ready.
