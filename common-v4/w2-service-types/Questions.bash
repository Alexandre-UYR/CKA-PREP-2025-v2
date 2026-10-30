# Question: Three Services, one of them broken
#
# In the `svcs` namespace there is a Deployment `web` (nginx, 2 replicas, labels
# app=web) and a Service `web-clusterip` of type ClusterIP, port 80 -> targetPort
# 80.
#
# The Deployment's pods are running and Ready, but the Service has NO
# ENDPOINTS.
#
# Task:
# 1. Find out why the Service `web-clusterip` has no endpoints, and fix it.
# 2. Fix it IN PLACE. Do not delete and re-create `web-clusterip` - the
#    Service has to stay the same object it was before.
# 3. Expose the same Deployment two more ways:
#    - Service `web-nodeport`: type NodePort, port 80 -> targetPort 80,
#      nodePort 30080.
#    - Service `web-lb`: type LoadBalancer, port 80 -> targetPort 80.
# 4. All three Services must select the Deployment's pods, and all three must
#    have endpoints.
#
# Note: the LoadBalancer's EXTERNAL-IP is not part of the answer. See the
# prerequisites before you start.
