# Question: An object that was never applied
#
# The Service `svc` in the `traps` namespace exposes port 80 to the container's
# port 80. It needs to expose port 8080 to the container's port 80 instead.
#
# Task:
# 1. Change the Service with `kubectl apply`, and save the manifest you
#    applied to /root/svc.yaml.
# 2. Be careful. The Service was CREATED with `kubectl create`, not APPLIED, so
#    it carries no last-applied configuration. kubectl has no baseline to diff
#    against, and it will tell you so - until it has one it will not manage
#    the fields you did not mention.
#
# The Service must still select the pods of the Deployment `web`, and it must
# have at least one endpoint.
#
# The Deployment `web` is not part of the question: leave it alone.
