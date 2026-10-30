# Question: Scale, update, roll back
#
# Task:
# Deployment `api` in namespace `release` runs two replicas of nginx:1.25.
#
# Scale it to 5 replicas, then update the image to nginx:1.26 and wait for
# the rollout to finish. Then roll back to the previous revision and scale it
# back to 2 replicas.
#
# Do not delete and re-create the Deployment.
