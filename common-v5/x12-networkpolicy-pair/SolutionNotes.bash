# 1. The policy that opens the door - to the labelled Pod, and to nobody else.
#
#    The client carries the label and lives in the frontend namespace, so the
#    rule needs a namespaceSelector as well as the podSelector. The frontend
#    namespace is labelled name=frontend, and every namespace also carries
#    kubernetes.io/metadata.name.
cat <<'EOF' | kubectl -n netpol apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-httpd-from-labelled
  namespace: netpol
spec:
  podSelector:
    matchLabels:
      app: httpd
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: frontend
          podSelector:
            matchLabels:
              httpd-access: "true"
      ports:
        - protocol: TCP
          port: 80
EOF

# 2. The policy that shuts the other door.
#
#    There is no ingress rule at all, which is the deny: a policy that selects
#    a Pod and lists no ingress rules isolates it completely. Nothing reaches
#    my-proxy, from any namespace.
cat <<'EOF' | kubectl -n netpol apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress-to-proxy
  namespace: netpol
spec:
  podSelector:
    matchLabels:
      app: proxy
  policyTypes:
    - Ingress
EOF

kubectl -n netpol get networkpolicy
# NAME                       POD-SELECTOR     AGE
# allow-httpd-from-labelled app=httpd        6s
# deny-all-ingress-to-proxy  app=proxy        6s

# 3. Prove the first one: the labelled client still gets in.
kubectl -n frontend exec client -- curl -s -o /dev/null -w '%{http_code}' \
  --max-time 10 http://my-httpd.netpol.svc.cluster.local
# 200

# 4. Prove the second one: my-app cannot reach my-proxy any more. Before the
#    policy this returned 200.
kubectl -n netpol exec my-app -- wget -S -O - -T 5 http://my-proxy.netpol.svc.cluster.local
# Connecting to my-proxy.netpol.svc.cluster.local (10.96.44.7:80)
#
# The connection is dropped, so wget waits for its timeout and gives up.
#
# The same command without the policy answers:
#   HTTP/1.1 200 OK
