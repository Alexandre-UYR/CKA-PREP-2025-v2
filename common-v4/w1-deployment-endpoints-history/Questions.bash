# Question: What the cluster actually says
#
# In the `cache` namespace there is a Deployment `cache` (memcached, 3 replicas)
# and a Service `cache` of type NodePort that exposes it on port 11211.
#
# Task:
# 1. Write the Service's ENDPOINTS to /root/q3.json, in JSON output format.
#    The file must contain the endpoint addresses of the pods the Service
#    selects.
# 2. Scale the Deployment to 5 replicas and wait for the rollout to finish.
# 3. Write the Deployment's ROLLOUT HISTORY to /root/q3.txt.
# 4. The Service must keep working: it has to select the pods, and the
#    nodePort must stay the same.
#
# Note: both files are graded. A file that exists but holds the wrong thing is
# not an answer.
