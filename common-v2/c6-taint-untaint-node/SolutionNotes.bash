# c6 — Taint and untaint: the reference answer
#
# Two nodes are involved. Say the payments node is worker1 and the do-not-use
# node is worker2.

# ---------------------------------------- 1. remove the do-not-use taint --

kubectl get nodes -o custom-columns='NAME:.metadata.name,TAINTS:.spec.taints[*].key'
# NAME     TAINTS
# worker1  dedicated
# worker2  do-not-use

# The trailing '-' removes the taint. It has to name the key, the value and
# the effect exactly as they are.
kubectl taint nodes worker2 do-not-use=true:NoSchedule-

kubectl get nodes -o custom-columns='NAME:.metadata.name,TAINTS:.spec.taints[*].key'
# NAME     TAINTS
# worker1  dedicated
# worker2  <none>

# The dedicated=payments taint on worker1 is left exactly where it was.

# ------------------------------------------- 2. a toleration on the template --

kubectl -n taints patch deployment workload --type=json \
  -p='[
        {"op": "add", "path": "/spec/template/spec/tolerations", "value": [
          {"key": "dedicated", "operator": "Equal", "value": "payments", "effect": "NoSchedule"}
        ]}
      ]'

# ------------------------------------- 3. a placement rule on the template --

# Every node carries kubernetes.io/hostname, whose value is the node's name.
kubectl get nodes --show-labels | grep worker1
# worker1   ... kubernetes.io/hostname=worker1

kubectl -n taints patch deployment workload --type=merge \
  -p='{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"worker1"}}}}}'

# A nodeAffinity works just as well, and the grader accepts either:
#
# kubectl -n taints patch deployment workload --type=merge -p='
#   {"spec":{"template":{"spec":{"affinity":{"nodeAffinity":{
#     "requiredDuringSchedulingIgnoredDuringExecution":{"nodeSelectorTerms":[
#       {"matchExpressions":[{"key":"kubernetes.io/hostname","operator":"In","values":["worker1"]}]}]}
#   }}}}}}'

# ----------------------------------------------------- 4. check the result ---

# Patching the template makes the Deployment roll a new pod, which is the one
# the scheduler places.
kubectl -n taints rollout status deployment workload

kubectl -n taints get pods -o wide
# NAME                        READY   STATUS    RESTARTS   AGE   NODE
# workload-6d9c7f5b4c-hz2qx   1/1     Running   0          12s   worker1

kubectl -n taints get pod -l app=workload -o jsonpath='{.items[0].spec.nodeName}{"\n"}'
# worker1

# The Deployment was patched, so it kept its UID.
kubectl -n taints get deployment workload -o jsonpath='{.metadata.uid}{"\n"}'
# 8f2c1d7e-6b9a-4a3c-9d21-0b5e7c1a2f30   <- same as before the patch

# ------------------------------------------------------- 5. the idempotent way --

# Editing a copy of the Deployment and applying it also keeps the UID:
#
# kubectl -n taints get deployment workload -o yaml > workload.yaml
# # ... add the toleration and the nodeSelector to workload.yaml ...
# kubectl apply -f workload.yaml
#
# Delete-and-recreate does NOT: the UID changes, and the task is not satisfied.
