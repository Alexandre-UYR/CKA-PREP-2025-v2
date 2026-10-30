# Question: The API server that says no
#
# Creating a workload in namespace `quota` is refused by the API server. The
# namespace carries a ResourceQuota that demands CPU and memory requests AND
# limits, and a manifest that declares none of them is rejected. The setup
# tried it and was told:
#
#   Error creating: pods "app-xxxxx" is forbidden: failed quota:
#   compute-quota: must specify limits.cpu, limits.memory, requests.cpu,
#   requests.memory
#
# A ResourceQuota is enforced at ADMISSION time by the API server, not by a
# controller: the object is simply refused, so nothing is created and there
# is no object to look at afterwards - only the error, which names the quota
# and the fields that are missing.
#
# Task:
# 1. Create a Deployment `app` (image nginx, 1 replica) in namespace `quota`
#    that the API server ACCEPTS, with the resources the quota demands.
# 2. Then prove it actually runs: the Pod Running, one ready container, one
#    ready replica.
#
# Two routes work:
#   - declare requests.cpu, requests.memory, limits.cpu and limits.memory on
#     the container yourself;
#   - or let the namespace's LimitRange `defaults` supply the memory values
#     and declare the CPU ones yourself.
#
# The ResourceQuota and the LimitRange are pre-state: the quota is what makes
# the exercise an exercise, so do not delete it and do not raise its limits.
