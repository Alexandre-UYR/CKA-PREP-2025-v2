# Question: One door open, one door shut
#
# In the `netpol` namespace there are three Pods: `my-httpd`, `my-proxy` and
# `my-app`. In the `frontend` namespace there is a Pod called `client`.
#
# Task:
# 1. Write a NetworkPolicy that allows ingress to `my-httpd` only from Pods
#    labelled `httpd-access=true`, and from nobody else.
# 2. Write a second NetworkPolicy that stops `my-app` reaching `my-proxy` at
#    all.
# 3. Prove both. A Pod with the right label must still reach `my-httpd`, and
#    `my-app` must not reach `my-proxy`.
#
# Both policies go in the `netpol` namespace.
