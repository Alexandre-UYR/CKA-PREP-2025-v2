# Question: Ingress with several rules
#
# Task:
# In the `ingress` namespace, create an Ingress named `web` with
# `ingressClassName: nginx` and two rules.
#
# Rule one, host `shop.example.com`:
#   - path `/a` (pathType Prefix) -> Service `app-a`, port 80
#   - path `/b` (pathType Prefix) -> Service `app-b`, port 80
#
# Rule two, host `api.example.com`:
#   - path `/` (pathType Prefix) -> Service `app-a`, port 80
#
# Both Deployments `app-a` and `app-b` are already running, and the Services
# `app-a` and `app-b` already exist.
