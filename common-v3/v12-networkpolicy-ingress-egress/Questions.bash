# Question: Open the door, but only that door
#
# The api runs in namespace `pol`, behind a Service `api` on port 80. There is
# no NetworkPolicy in the cluster at all, so right now the api is reachable
# from every namespace - including the ones that should never have heard of it.
#
# Task:
# 1. Write a NetworkPolicy `api` in namespace `pol` that allows INGRESS to the
#    api pods on TCP port 80 ONLY from pods in the `client` namespace. That
#    namespace is labelled `name=client`; the `other` namespace is not, and must
#    stay locked out.
# 2. In the same policy, allow EGRESS from the api pods ONLY to DNS - UDP and
#    TCP port 53. The api must not be able to reach anything else, and it must
#    still be able to resolve names.
# 3. Prove it, from inside the cluster:
#    - from the `client` namespace, `http://api.pol.svc.cluster.local` returns 200
#    - from the `other` namespace, the same URL does not
#    - from a pod in `pol`, names still resolve
