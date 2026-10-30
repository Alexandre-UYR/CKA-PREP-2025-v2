# 1. Install the Gateway API CRDs (standard channel, v1.2.0).
#
# The CRDs are cluster-scoped. They are the API types only - no controller is
# installed, and none is needed for this question.
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

kubectl get crd | grep gateway.networking.k8s.io
# gateways.gateway.networking.k8s.io
# gatewayclasses.gateway.networking.k8s.io
# grpcroutes.gateway.networking.k8s.io
# httproutes.gateway.networking.k8s.io
# referencegrants.gateway.networking.k8s.io
# referencepolicies.gateway.networking.k8s.io

# 2. The Gateway.
cat <<'EOF' | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: edge
  namespace: default
spec:
  gatewayClassName: nginx
  listeners:
    - name: http
      protocol: HTTP
      port: 80
EOF

# 3. The HTTPRoute.
cat <<'EOF' | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: edge-route
  namespace: default
spec:
  parentRefs:
    - name: edge
  hostnames:
    - app.example.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: web
          port: 80
EOF

# The Gateway and the HTTPRoute do not have to be in the same namespace. If
# they are split, remember that a backendRef without an explicit `namespace`
# resolves against the HTTPRoute's own namespace:
#
#   kind: HTTPRoute
#   metadata:
#     name: edge-route
#     namespace: routes
#   spec:
#     parentRefs:
#       - name: edge
#         namespace: default
#     rules:
#       - backendRefs:
#           - name: web
#             namespace: default
#             port: 80

# Check the result.
kubectl get gateways.gateway.networking.k8s.io -A
kubectl get httproutes.gateway.networking.k8s.io -A

kubectl -n default get gateway edge -o yaml
kubectl -n default get httproute edge-route -o yaml

# The Gateway's status will stay unprogrammed: no controller was installed.
# That is expected and the task says it is not required.
kubectl -n default get gateway edge
# NAME   CLASS   ADDRESS   PROGRAMMED   AGE
# edge   nginx   none      False        10s
