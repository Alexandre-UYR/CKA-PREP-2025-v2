# 1. Look at the workload and at what protects it.
kubectl -n pdb get deploy api
# NAME   READY   UP-TO-DATE   AVAILABLE   AGE
# api    3/3     3            3           30s

kubectl -n pdb get pods -l app=api
# NAME            READY   STATUS    RESTARTS   AGE
# api-7d9f8c6b5d   1/1     Running   0          30s
# api-84c7b9f66   1/1     Running   0          30s
# api-x2m5n4kl9   1/1     Running   0          30s

kubectl -n pdb get pdb
# No resources found in pdb namespace.

# Nothing protects these pods: a drain can take all three at once.

# 2. Write the budget. Either of the two forms is correct - with three
#    replicas, "at most one unavailable" and "at least two available" are the
#    same budget. Only one of them may be set.
#
#    This one uses maxUnavailable:
cat <<'EOF' | kubectl apply -n pdb -f -
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: api-pdb
  namespace: pdb
spec:
  maxUnavailable: 1
  selector:
    matchLabels:
      app: api
EOF

# Or, the same budget written the other way:
#
#   spec:
#     minAvailable: 2
#     selector:
#       matchLabels:
#         app: api

# 3. Check the ALLOWED DISRUPTIONS column - that is the live proof.
kubectl -n pdb get pdb api-pdb
# NAME      MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   CURRENT HEALTHY   DESIRED HEALTHY   EXPECTED PODS
# api-pdb   <none>         1                  1                     3                 2                 3

# ALLOWED DISRUPTIONS is 1, and CURRENT HEALTHY is 3 - the budget is looking at
# the api pods, not at an empty set.

# 4. What the wrong selectors look like, for comparison:
#
#    selector: {}                      -> an empty selector matches EVERY pod in
#                                         the namespace. It is not "no selector".
#
#    selector:
#      matchLabels:
#        tier: api                    -> the api pods do not carry that label, so
#                                         the budget matches nothing:
#
#     NAME      MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   CURRENT HEALTHY   DESIRED HEALTHY   EXPECTED PODS
#     api-pdb   2               0                  0                     0                 0                 0
#
# That budget looks perfectly well-formed in the YAML and protects nothing.

# A note on what a budget does: it constrains VOLUNTARY disruption - a node
# drain, an autoscaler removing a pod, an eviction through the eviction API.
# It does nothing for a node that fails or a container that is killed.
