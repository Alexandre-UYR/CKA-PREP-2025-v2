# Question: The pod that will not start
#
# The Pod `web` in the `diag` namespace has been stuck since it was created. It
# never runs.
#
# Task:
# 1. Find out why. The Pod's status only says it is waiting; the reason is
#    written somewhere else.
# 2. Fix it so that the Pod runs, and so that the environment variable it
#    expects is actually set. The variable it expects is `MODE`, with the value
#    `prod`.
# 3. Do NOT delete and re-create the Pod. Fix the environment around the Pod
#    that is already there.
#
# Verify the answer from inside the Pod: the variable must be set, not merely
# the Pod must be green.
