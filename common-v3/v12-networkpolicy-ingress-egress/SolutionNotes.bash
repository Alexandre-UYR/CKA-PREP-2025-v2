# 1. See what is there.
kubectl get ns --show-labels | grep -E 'client|other'
# client   name=client
# other    <no labels>

kubectl -n pol get deploy api --show-labels
# NAME   READY   UP-TO-DATE   AVAILABLE   AGE
# api    1/1     1            1           2m

# 2. Write the policy. Both directions live in one object.
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api
  namespace: pol
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: client
      ports:
        - protocol: TCP
          port: 80
  egress:
    - ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
EOF

# 3. Read it back.
kubectl -n pol get networkpolicy api -o yaml

# 4. Prove it, from inside the cluster.
kubectl -n client exec probe -- curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 http://api.pol.svc.cluster.local
# 200

kubectl -n other exec probe -- curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 http://api.pol.svc.cluster.local
# 000        <- the connection never completes; the packet is dropped

APIPOD=$(kubectl -n pol get pods -l app=api -o jsonpath='{.items[0].metadata.name}')
kubectl -n pol exec "$APIPOD" -- nslookup kubernetes.default.svc.cluster.local
# Server:		10.43.0.10
# Address:	10.43.0.10:53
#
# Name:	kubernetes.default.svc.cluster.local
# Address: 10.96.0.1

# The `to` is left out of the egress rule on purpose. The rule allows port 53
# to any destination, which is what DNS needs: the cluster DNS service is
# reached by ClusterIP, and a `to` that names only the kube-system namespace
# misses the node-local resolver on some clusters. Leaving `to` out keeps the
# rule narrow by port, and port 53 is the part that matters.
#
# What you must not write is an empty destination:
#
#   egress:
#     - to: []            <- matches nothing at all
#     - to:
#         - ipBlock:
#             cidr: 0.0.0.0/0    <- allows the api to reach the whole world
#
# Both look like "allow DNS" and neither is.
