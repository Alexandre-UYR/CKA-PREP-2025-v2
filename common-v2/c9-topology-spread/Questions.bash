# Question: Spread pods across nodes
#
# Task:
# In the topology namespace there is a Deployment named spread with four
# replicas and no topologySpreadConstraints.
#
# 1. Add a topologySpreadConstraint to the Deployment's pod template so that
#    its pods are spread across the nodes:
#      - maxSkew: 1
#      - topologyKey: kubernetes.io/hostname
#      - whenUnsatisfiable: ScheduleAnyway
#      - a labelSelector that matches app=spread
# 2. Scale the Deployment to 8 replicas.
#
# All 8 replicas must be ready, and the running pods must be spread over at
# least two different nodes.
