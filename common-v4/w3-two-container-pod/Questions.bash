# Question: A Pod with two containers
#
# The `multi` namespace holds a Deployment `single` that runs one nginx
# container. It is there as a reference for what one container looks like.
#
# Task:
# 1. Create a Pod `multi-pod` in namespace `multi` with TWO containers:
#    `busy1` and `busy2`. Both must use the image busybox:1.36.
# 2. Both containers must run a command that keeps them alive for at least
#    five minutes: `sleep 100000`.
# 3. Label the Pod `env=test`.
# 4. The Pod must still be Running five minutes from now, and neither
#    container may have restarted.
#
# Note: a Pod with two containers shares one network namespace and one
# lifecycle. If one container exits, the Pod is restarted as a whole - so
# both commands have to be long-running.
