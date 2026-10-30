# Question: Move the routing to the new API without changing the outside
#
# In the namespace `gw` there is an Ingress `web`. It serves the host
# gateway.web.k8s.local over TLS, using the Secret `web-tls`, and sends every
# path to the Service `web` on port 80.
#
# The Ingress is being replaced by the Gateway API, and the outside has to
# look exactly the same: the same hostname, the same TLS certificate, the same
# path, the same backend.
#
# Task:
# 1. Install the Gateway API CRDs.
# 2. Create the Gateway `web-gateway` in the namespace `gw`:
#    - it uses the gateway class `nginx-class`
#    - it has a listener that terminates TLS with the Secret `web-tls` and
#      listens for the host gateway.web.k8s.local
# 3. Create the HTTPRoute `web-route` in the namespace `gw` carrying the same
#    routing rules as the Ingress:
#    - it belongs to the Gateway `web-gateway`
#    - it serves the host gateway.web.k8s.local
#    - it matches the path prefix / and sends it to the Service `web` on
#      port 80
# 4. When the Gateway is doing the work, remove the Ingress. The hostname has
#    to be served by exactly one of them, not both.
#
# The Deployment `web` and the Service `web` stay exactly as they are.
