# The Ingress: one class, two rules, three paths.
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web
  namespace: ingress
spec:
  ingressClassName: nginx
  rules:
    # Rule one: the shop, two paths, two different backends.
    - host: shop.example.com
      http:
        paths:
          - path: /a
            pathType: Prefix
            backend:
              service:
                name: app-a
                port:
                  number: 80
          - path: /b
            pathType: Prefix
            backend:
              service:
                name: app-b
                port:
                  number: 80
    # Rule two: the api, everything under it goes to app-a.
    - host: api.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app-a
                port:
                  number: 80
EOF

kubectl -n ingress get ingress web
# NAME   CLASS   HOSTS                       ADDRESS   PORTS   AGE
# web    nginx   shop.example.com,api.example.com            80      20s

# What the rules look like in the stored object:
kubectl -n ingress get ingress web -o yaml
# spec:
#   ingressClassName: nginx
#   rules:
#   - host: shop.example.com
#     http:
#       paths:
#       - backend:
#           service:
#             name: app-a
#             port:
#               number: 80
#         path: /a
#         pathType: Prefix
#       - backend:
#           service:
#             name: app-b
#             port:
#               number: 80
#         path: /b
#         pathType: Prefix
#   - host: api.example.com
#     http:
#       paths:
#       - backend:
#           service:
#             name: app-a
#             port:
#               number: 80
#         path: /
#         pathType: Prefix

# The backends resolve to real endpoints, because the Services select the
# Deployments' pods:
kubectl -n ingress get endpoints app-a app-b
# NAME     ENDPOINTS          AGE
# app-a    10.244.0.11:80     25s
# app-b    10.244.0.12:80     25s

# There is no ingress controller in this cluster, so there is no ADDRESS and
# nothing answers on the object yet. That does not make the Ingress wrong -
# the object is what the question asks for. To serve it for real you would
# install a controller for class nginx and point the two hosts at it:
#
#   echo "<controller-ip> shop.example.com api.example.com" | sudo tee -a /etc/hosts
#   curl -H "Host: shop.example.com" http://<controller-ip>/a
#   curl -H "Host: shop.example.com" http://<controller-ip>/b
#   curl -H "Host: api.example.com"  http://<controller-ip>/anything
