# Question: The pod that has been Pending for ten minutes
#
# The Pod `stuck` in the `sched` namespace has been Pending for ten minutes.
# The image is fine and the Pod spec is valid - the cluster simply has not
# been able to place it.
#
# Task:
# 1. Read what the scheduler actually said. `kubectl describe pod stuck` puts
#    the scheduler's verdict in the Events section. Read it - do not guess.
# 2. Work out why the Pod cannot be placed. There may be more than one
#    reason, and they may not all be on the Pod.
# 3. Put the Pod on a node that can actually run it. The Pod must end up
#    Running.
# 4. You may re-create the Pod if you have to: a Pod's nodeSelector is
#    immutable, so it cannot be edited in place.
#
# When you are done, say which node the Pod landed on and what that node's
# state is: Ready? cordoned? tainted?
