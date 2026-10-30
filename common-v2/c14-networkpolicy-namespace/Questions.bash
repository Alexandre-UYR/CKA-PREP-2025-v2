# Question: Allow ingress from one namespace only
#
# Task:
# Create a NetworkPolicy `allow-frontend` in namespace `netpol` that allows
# ingress to the `api` pods on TCP port 80 ONLY from pods in the `frontend`
# namespace, and blocks every other source. Traffic from the `other` namespace
# must not get through.
#
# The `frontend` namespace carries the label `name=frontend` - that is how a
# namespaceSelector picks it out.
#
# Verify it, from both sides:
#   - a pod in `frontend` reaches http://api.netpol.svc.cluster.local and gets
#     HTTP 200
#   - a pod in `other` does not reach it (any non-200 result counts as blocked)
#
# Probe with:
#   kubectl -n <ns> run probe --rm -i --restart=Never --image=curlimages/curl -- \
#     curl -s -m 5 -o /dev/null -w "%{http_code}" http://api.netpol.svc.cluster.local
#
# Clean the probe pods up when you are done.
