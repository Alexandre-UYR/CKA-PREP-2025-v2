# Question: Service on a named port
#
# Task:
# In the namedport namespace, the Deployment `web` is already running a single
# nginx container that declares no ports.
#
# Declare a container port named `http` on port 80 (protocol TCP) in that
# container, and expose it with a Service named `web-svc` in the same
# namespace:
#   - the Service port is named `http`
#   - the Service port is 80
#   - the Service targetPort is `http` - the NAME, not the number
#   - the protocol is TCP
#
# The Service must actually select the pods: it must end up with at least one
# endpoint address.
