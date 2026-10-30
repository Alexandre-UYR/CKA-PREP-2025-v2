# The policy.
#
# Two things do the work here:
#   - the podSelector picks out the api pods, which isolates them for ingress
#   - the single ingress rule says who may talk to them and on which port
#
# Everything that is not explicitly allowed is dropped, so `other` is denied
# without a rule naming it.

cat <<'EOF' > netpol.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend
  namespace: netpol
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: frontend
      ports:
        - protocol: TCP
          port: 80
EOF

kubectl apply -f netpol.yaml

# Check what the API server stored.
kubectl -n netpol get netpol allow-frontend -o yaml

# The allowed side: this must answer 200.
kubectl -n frontend run probe --rm -i --restart=Never --image=curlimages/curl -- \
  curl -s -m 5 -o /dev/null -w "%{http_code}\n" http://api.netpol.svc.cluster.local
# 200

# The denied side: the connection is dropped, so curl times out and prints 000.
kubectl -n other run probe --rm -i --restart=Never --image=curlimages/curl -- \
  curl -s -m 5 -o /dev/null -w "%{http_code}\n" http://api.netpol.svc.cluster.local
# 000

# Clean the probe pods up.
kubectl -n frontend delete pod probe --ignore-not-found
kubectl -n other delete pod probe --ignore-not-found

# If the denied probe answered 200, the policy is not being enforced: check
# which CNI is installed. A CNI that does not implement NetworkPolicy accepts
# the object and then ignores it.
#
# A quick look at the rules from the inside:
kubectl -n netpol describe netpol allow-frontend

# The same policy piped straight into the API server, if you prefer to skip the
# manifest file:
#
#   kubectl -n netpol apply -f - <<'EOF'
#   apiVersion: networking.k8s.io/v1
#   kind: NetworkPolicy
#   metadata:
#     name: allow-frontend
#   spec:
#     podSelector:
#       matchLabels:
#         app: api
#     policyTypes:
#       - Ingress
#     ingress:
#       - from:
#           - namespaceSelector:
#               matchLabels:
#                 name: frontend
#         ports:
#           - protocol: TCP
#             port: 80
#   EOF
