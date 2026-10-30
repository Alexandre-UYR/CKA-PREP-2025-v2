# 1. Install the Gateway API CRDs.
#
# The Gateway API is not part of Kubernetes: it is a set of CRDs that have to
# be installed separately. The standard channel has everything that went GA -
# GatewayClass, Gateway, HTTPRoute and ReferenceGrant:
#
#   https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
#
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

# The `experimental` channel carries the same resources plus the ones still in
# alpha; it is not needed here.
#
# Any v1.1 or later release of the standard channel does the job. Check what
# you got:
kubectl get crd | grep gateway.networking.k8s.io
# gatewayclasses.gateway.networking.k8s.io   2024-11-12 00:00:00
# gateways.gateway.networking.k8s.io          2024-11-12 00:00:00
# httproutes.gateway.networking.k8s.io        2024-11-12 00:00:00
#
# The GatewayClass `nginx-class` is already there - its CRD was never removed
# - so there is nothing to create:
kubectl get gatewayclass
# NAME         CONTROLLER                              ACCEPTED   AGE
# nginx-class  example.net/nginx-gateway-controller   True       5m

# 2. The Gateway.
#
# The TLS that lived in the Ingress's spec.tls block now lives on the
# LISTENER. A listener has one hostname, one port and one protocol - so the
# hostname the Ingress used in its rule is the hostname the listener carries.
cat <<'EOF' | kubectl -n gw apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: web-gateway
  namespace: gw
spec:
  gatewayClassName: nginx-class
  listeners:
    - name: https
      protocol: HTTPS
      port: 443
      hostname: gateway.web.k8s.local
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: web-tls
EOF

# 3. The HTTPRoute.
#
# The Ingress's rules become the HTTPRoute's rules: the hostname goes in
# spec.hostnames, the path match goes in the rule, and the backend goes in
# backendRefs. The Gateway the route belongs to is named in parentRefs.
cat <<'EOF' | kubectl -n gw apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: web-route
  namespace: gw
spec:
  parentRefs:
    - name: web-gateway
  hostnames:
    - gateway.web.k8s.local
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: web
          port: 80
EOF

# 4. Remove the Ingress.
#
# The hostname must be served by exactly one object. While both are there,
# two things claim gateway.web.k8s.local and it is not clear which one the
# traffic reaches.
kubectl -n gw delete ingress web

# Have a look at what the outside looks like now:
kubectl -n gw get gateway,httproute
# NAME           AGE
# httproute/web-route   10s
#
# NAME            AGE
# gateway/web-gateway   10s

kubectl -n gw get gateway web-gateway -o yaml
# spec:
#   gatewayClassName: nginx-class
#   listeners:
#   - hostname: gateway.web.k8s.local
#     port: 443
#     protocol: HTTPS
#     tls:
#       certificateRefs:
#       - kind: Secret
#         name: web-tls
#       mode: Terminate

# The Secret was not touched, so the certificate served is the same one the
# Ingress served:
kubectl -n gw get secret web-tls -o jsonpath='{.type}{"\n"}'
# kubernetes.io/tls

# The rewrite-target annotation has no direct equivalent in the Gateway API:
# it was an nginx-ingress-specific instruction, and the equivalent in the
# Gateway API is a URLRewrite filter, which is not part of the standard
# channel and not needed here - the backend serves / anyway.

# Nothing runs the Gateway: the controller named by the GatewayClass
# (example.net/nginx-gateway-controller) does not exist in this cluster, so
# the Gateway will never report itself as Programmed. That is expected here -
# the question is about moving the configuration across, not about serving
# traffic.
kubectl -n gw get gateway web-gateway -o jsonpath='{.status.conditions}{"\n"}'
# []
