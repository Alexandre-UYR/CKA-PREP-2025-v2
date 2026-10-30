# Question: Two hosts, two certificates
#
# The api runs in namespace `ing`, behind a Service `api` on port 80. Two TLS
# secrets already exist there: `api-tls` holds a certificate for
# api.example.com, and `alt-tls` holds one for alt.example.com.
#
# Task:
# 1. Create an Ingress `web` in namespace `ing` that terminates TLS for TWO
#    hosts:
#    - api.example.com, using the secret `api-tls`
#    - alt.example.com, using the secret `alt-tls`
# 2. The host api.example.com serves the path /api (pathType Prefix) and the
#    host alt.example.com serves the path / (pathType Prefix). Both route to
#    Service `api`, port 80.
# 3. Use `ingressClassName: nginx`, and add the rewrite annotation so that a
#    request to /api is rewritten to /.
