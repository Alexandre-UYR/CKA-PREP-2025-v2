# Question: The Service's port is not the container's port
#
# In the `web` namespace there is a Deployment `site` (nginx:latest, 5 replicas,
# pod labels app=site). Its container already declares a container port NAMED
# `http`, and that port is 80.
#
# Task:
# Expose the Deployment `site` with a Service `site-svc` in the `web`
# namespace.
#
#   - the Service's port must be NAMED `http`
#   - the Service's port must be 8080
#   - the Service's targetPort must be `http` - the NAME of the container's
#     port, not the number 80
#
# Confirm that the Service really selects the pods: it must have endpoints.
