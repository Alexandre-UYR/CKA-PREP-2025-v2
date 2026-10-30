# Question: Protect the workload from voluntary disruption
#
# The `api` Deployment in the `pdb` namespace is healthy and has three
# replicas. Nothing protects it: `kubectl -n pdb get pdb` comes back empty,
# so a node drain can take all three pods away at once.
#
# Task:
# 1. Protect the `api` Deployment in namespace `pdb` from voluntary disruption.
# 2. Create a PodDisruptionBudget `api-pdb` that allows AT MOST ONE of its
#    pods to be disrupted at a time.
# 3. Make sure it actually selects the api pods - a budget whose selector
#    matches nothing protects nothing.
# 4. Check the ALLOWED DISRUPTIONS column to confirm it took effect:
#
#        kubectl -n pdb get pdb api-pdb
#
# Remember what a PodDisruptionBudget does and does not do: it constrains
# VOLUNTARY disruption (a node drain, an autoscaler removing a pod), not a
# node that fails.
