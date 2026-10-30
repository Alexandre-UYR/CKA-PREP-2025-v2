# Question: Two probes, both wrong
#
# The Deployment `probed` in the `probe` namespace is running, but its pods are
# never Ready, and the liveness probe is going to start killing them.
#
# Task:
# 1. Fix the readiness probe so that the pods become Ready.
# 2. Fix the liveness probe so that it stops pointing at something that does
#    not exist, and the containers stay up.
# 3. Fix them ON THE RUNNING DEPLOYMENT. The pod template can be edited in
#    place; the Deployment must not be deleted and re-created.
#
# The pods must end up Running and Ready, with a restart count of 0.
#
# Watch the arithmetic. A liveness probe is allowed
#
#   initialDelaySeconds + periodSeconds x failureThreshold
#
# seconds before the kubelet kills the container, and a readiness probe that
# fails keeps a pod out of the Service's endpoints for as long as it fails.
