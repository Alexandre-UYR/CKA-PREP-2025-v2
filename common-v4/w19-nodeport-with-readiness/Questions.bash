# Question: Reachable, but only once it is ready
#
# In the `edge` namespace there is a Deployment `catalog` (nginx:1.25, 2
# replicas, pod labels app=catalog). It has no Service and no readiness probe.
#
# Task:
# 1. Create a Service `catalog-svc` in the `edge` namespace:
#    - type NodePort
#    - nodePort 30080
#    - port 80
#    - targetPort 80
#    - selecting the Deployment's pods
#
# 2. Add a readiness probe to the Deployment `catalog` so that the Service
#    only sends traffic to pods that are actually serving:
#    - an httpGet on path `/` and port 80
#    - initialDelaySeconds: 2
#    - periodSeconds: 5
#
# The Service must have endpoints, and the pods must be Ready.
