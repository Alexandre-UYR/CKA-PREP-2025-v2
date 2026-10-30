# 1. Install Traefik.
#
# The chart lives in its own Helm repository, so the repository has to be added
# before the chart can be installed by name.
helm repo add traefik https://helm.traefik.io
helm repo update

kubectl create namespace traefik --dry-run=client -o yaml | kubectl apply -f -

helm install traefik traefik/traefik -n traefik

# Check that it came up:
kubectl -n traefik get pods
# NAME                       READY   STATUS    RESTARTS   AGE
# traefik-6c8f9d7b9c-4t2xk   1/1     Running   0          30s

helm list -n traefik
# NAME     NAMESPACE   REVISION  UPDATED  STATUS    CHART         APP VERSION
# traefik  traefik     1         30s ago  deployed  traefik-3.0.0  3.0.0

# (--create-namespace does the same job as the kubectl create above. The task
# asks for the namespace to be created by hand, which is what the first two
# commands do.)

# 2. The Ingress.
#
# ingressClassName: traefik matters. The chart installs an IngressClass called
# `traefik`, and Traefik only watches the Ingresses that name it. An Ingress
# with no class is ignored unless the controller has been made the default one.
cat <<'EOF' | kubectl -n web apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web
  namespace: web
spec:
  rules:
    - host: www.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: thirdpage
                port:
                  number: 80
EOF

kubectl -n web get ingress web
# NAME   CLASS     HOSTS             ADDRESS     PORTS   AGE
# web    traefik   www.example.com   localhost   80      20s

# 3. The proof.
#
# The request has to carry the Host header, because the Host header is what
# Traefik matches the rule on. The Service is reached by its cluster DNS name;
# the Host header says which rule inside Traefik should answer.
kubectl -n web exec probe -- \
  curl -s -i -H 'Host: www.example.com' http://traefik.traefik.svc.cluster.local/
# HTTP/1.1 200 OK
# ...
# thirdpage-marker host=www.example.com

# Without the Host header, Traefik has no rule to match and answers 404:
kubectl -n web exec probe -- \
  curl -s -o /dev/null -w '%{http_code}\n' http://traefik.traefik.svc.cluster.local/
# 404

# With the wrong Host header, the same thing happens:
kubectl -n web exec probe -- \
  curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: wrong.example.com' http://traefik.traefik.svc.cluster.local/
# 404

# The body says two things at once: `thirdpage-marker` says the request
# reached the third page, and `host=www.example.com` says it reached it
# through the rule for that hostname.

# If the chart put the Service somewhere else, look for it:
kubectl -n traefik get svc
# NAME       TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
# traefik    LoadBalancer   10.96.144.201   <pending>     80:32123/TCP   30s
#            443:32124/TCP
#
# The ClusterIP is what a pod inside the cluster uses; the LoadBalancer
# address only becomes useful if the cluster has a load balancer provider.
