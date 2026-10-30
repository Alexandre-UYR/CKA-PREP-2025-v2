# Question: Horizontal autoscaling
#
# Task:
# In the autoscale namespace, create a HorizontalPodAutoscaler named web-hpa
# that targets the existing Deployment `web`:
#   - minimum 2 pods
#   - maximum 8 pods
#   - target 60% CPU utilisation per pod
#   - a scaleDown stabilisation window of 60 seconds
#
# Leave the `web` Deployment alone - do not delete it and re-create it. The
# HPA has to point at the Deployment that is already running.
