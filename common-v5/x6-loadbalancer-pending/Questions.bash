# Question: The Service that will never get an address
#
# The Service `public` in the `edge` namespace has been pending for ten
# minutes with no external IP. On this cluster that is EXPECTED — there is
# nothing here that can give a Service a load-balancer address, so waiting is
# not the fix.
#
# But the traffic still has to reach the pods from outside the cluster.
#
# Task:
# 1. Change the Service so that it can be reached from outside the cluster:
#    - type NodePort
#    - nodePort 30080
#    - port 80
#    - targetPort 80
#    - the same selector it has now
# 2. Edit the Service. Do not delete it and create a new one.
# 3. Confirm it actually works: from inside the cluster, reach the Service
#    through its nodePort and get an HTTP 200 back.
