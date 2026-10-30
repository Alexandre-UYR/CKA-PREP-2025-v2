# c5 — Bring a NotReady node back: the reference answer
#
# The fix is on the node. Nothing here is an API-server command.

# ---------------------------------------------------------------- 1. find --

kubectl get nodes
# NAME        STATUS     ROLOS           AGE   VERSION
# minikube    Ready      control-plane   2d    v1.30.0
# worker1     NotReady   <none>          2d    v1.30.0

# The heartbeat in the describe output is the clue: it stops moving.
kubectl describe node worker1 | tail -20
#   Conditions:
#     Type             Status  LastHeartbeatTime           LastTransitionTime ...
#     Ready            False   <never>                      <never>            ...
#     MemoryPressure   False   Wed Oct 29 10:00:00 +0000    Wed Oct 29 10:00:00 ...
#   Addresses:
#     InternalIP:  172.18.0.3

# ------------------------------------------------------------ 2. fix it ---

# minikube:
minikube ssh -p default -- "systemctl enable --now kubelet"

# a normal cluster:
ssh root@172.18.0.3 "systemctl enable --now kubelet"

# a kind node (no SSH; the node is a container):
docker exec worker1 systemctl enable --now kubelet

# Starting it is enough to get the node back; enabling it is what stops the
# same thing happening again after a reboot. `enable --now` does both.

# ------------------------------------------------------------- 3. check ---

kubectl get nodes
# NAME        STATUS   ROLES           AGE   VERSION
# worker1     Ready    <none>          2d    v1.30.0

# The node reports a kubelet version, so a kubelet is talking to the API
# server again.
kubectl get node worker1 -o jsonpath='{.status.nodeInfo.kubeletVersion}'
# v1.30.0

# The kubelet is running AND enabled.
kubectl debug node/worker1 --image=busybox -- chroot /host systemctl is-active kubelet
# active
kubectl debug node/worker1 --image=busybox -- chroot /host systemctl is-enabled kubelet
# enabled

# The same two answers over SSH, if you prefer:
minikube ssh -p default -- "systemctl is-active kubelet; systemctl is-enabled kubelet"
# active
# enabled

# ------------------------------------------------------------- 4. clean ---

kubectl debug node/worker1 --image=busybox -- chroot /host systemctl list-units 'kubelet*'
# The helper pod is disposable - it stays around in the default namespace
# until you delete it:
kubectl get pods -n default | grep node-debugger
kubectl delete pod -n default worker1-debugger-xxxxx --ignore-not-found
