# Question: The Service that selects nothing
#
# The Service `cart-svc` in the `shop` namespace has no endpoints, although
# the pods of the Deployment `cart` are running and ready.
#
# Task:
# 1. Work out why the Service has no endpoints.
# 2. Fix it WITHOUT deleting and re-creating the Service, and WITHOUT changing
#    the labels on the pods. The pods must keep `app=cart-v2`, because
#    something else selects on those labels.
# 3. The Service has to select the pods that are actually there.
#
# When you are done, the Service must have at least two endpoints and the
# Deployment must still have two ready replicas.
