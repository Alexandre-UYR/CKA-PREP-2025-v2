# Question: The three Service types
#
# Task:
# Expose the `web` Deployment three ways in namespace `svctypes`:
#
#   - Service `web-clusterip`    type ClusterIP,    port 80, targetPort 80
#   - Service `web-nodeport`     type NodePort,     port 80, targetPort 80, nodePort 30080
#   - Service `web-loadbalancer` type LoadBalancer, port 80, targetPort 80
#
# All three must actually have endpoints - a Service with a selector that
# matches nothing is not exposing anything.
#
# Check them with:
#   kubectl -n svctypes get svc
#   kubectl -n svctypes get endpoints web-clusterip
