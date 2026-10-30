# Which node is which? `kubectl get nodes` says so: a cordoned node shows
# SchedulingDisabled in the STATUS column, and `kubectl describe node` lists
# the taints.
kubectl get nodes
# NAME       STATUS                     ROLES           AGE   VERSION
# node-1     Ready,SchedulingDisabled   <none>          10m   v1.32.0
# node-2     Ready                      <none>          10m   v1.32.0

kubectl describe node node-2 | sed -n '/Taints/p'
# Taints:  dedicated=payments:NoSchedule

# 1a. The cordoned node. `kubectl uncordon` clears the flag on the node.
#     Nothing already running is touched: a cordon only keeps NEW pods away.
kubectl uncordon node-1

kubectl get nodes
# NAME       STATUS     ROLES    AGE   VERSION
# node-1     Ready      <none>   10m   v1.32.0
# node-2     Ready      <none>   10m   v1.32.0

# 1b. The taint. The trailing minus removes it. Only THIS taint - if node-2
#     were a control-plane node, its own node-role taint belongs to the
#     cluster and must be left alone.
kubectl taint node node-2 dedicated=payments:NoSchedule-

kubectl get nodes
# NAME       STATUS   ROLES    AGE   VERSION
# node-1     Ready    <none>   10m   v1.32.0
# node-2     Ready    <none>   10m   v1.32.0

kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" taints: "}{range .spec.taints[*]}{.key}={.value}:{.effect}{" "}{end}{"\n"}{end}'
# node-1 taints:
# node-2 taints:

# 2. Label the node that carried the taint. A label is metadata: it does not
#    affect scheduling, and that is the point - it is there to be selected on.
kubectl label node node-2 Status=VIP

# 3. Prove the label is usable as a selector. Exactly one line comes back.
kubectl get nodes -l Status=VIP
# NAME     STATUS   ROLES    AGE   VERSION
# node-2   Ready    <none>   10m   v1.32.0
