# 1. Look at what is there.
kubectl -n ing get secret
# NAME      TYPE                DATA   AGE
# alt-tls   kubernetes.io/tls   2      1m
# api-tls   kubernetes.io/tls   2      1m

# Confirm which certificate is in which secret.
kubectl -n ing get secret api-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject
# subject=CN = api.example.com

kubectl -n ing get secret alt-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject
# subject=CN = alt.example.com

# 2. Write the Ingress. One TLS entry per host, one rule per host.
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web
  namespace: ing
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - api.example.com
      secretName: api-tls
    - hosts:
        - alt.example.com
      secretName: alt-tls
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: api
                port:
                  number: 80
    - host: alt.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: api
                port:
                  number: 80
EOF

# 3. Read it back.
kubectl -n ing get ingress web -o yaml

# The two TLS entries are the point. `tls` is a list, and each entry names the
# Secret that holds the certificate for the host(s) in that entry. Listing both
# hosts under one entry would give both of them the same certificate - the one
# in the single secretName - so the second host would serve the wrong one and
# every client would get a name mismatch.
#
# `pathType` is not optional in networking.k8s.io/v1. The API server rejects
# the Ingress without it, so the Ingress you create is already the one the
# server accepted.
#
# The rewrite annotation tells the ingress controller to replace the matched
# path with the value of the annotation, so /api is rewritten to / before the
# request reaches the Service.
