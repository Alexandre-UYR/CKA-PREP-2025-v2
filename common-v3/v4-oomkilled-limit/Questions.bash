# Question: The pod that keeps being killed
#
# The Deployment `greedy` in the `oom` namespace will not stay up. Its pod is
# restarting over and over.
#
# Task:
# 1. Find out what is actually killing the container. `kubectl get pods` tells
#    you it is restarting; the real reason is in the pod's status and events.
# 2. Fix it so the pod runs and stays running.
# 3. The container must keep a memory limit - but it has to be one the
#    container can actually live within. Do not simply remove the limit.
# 4. Leave the Deployment in place; fix it in place rather than deleting and
#    re-creating it.
#
# Verify that the pod stays up: watch the restart count, not just the phase.
