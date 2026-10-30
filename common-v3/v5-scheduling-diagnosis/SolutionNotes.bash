# 1. Read the scheduler's verdict. Do not guess - the Events section says
#    exactly why the pod was not placed.
kubectl -n sched describe pod stuck
# Status:  Pending
# Events:
#   Type     Reason            Age   From               Message
#   ----     ------            ----  ----               -------
#   Warning  FailedScheduling  12s   default-scheduler  0/2 nodes are available: 2 node(s) didn't match Pod's node affinity/selector.
#
# That is the FIRST of the three reasons. The pod asks for disk=ssd:
kubectl -n sched get pod stuck -o jsonpath='{.spec.nodeSelector}'
# {"disk":"ssd"}
#
# ...and no node has that label:
kubectl get nodes -L disk
# NAME            STATUS   ROLES           AGE   VERSION
# kind-worker     Ready    worker          10m   v1.31.0
# kind-worker2    Ready    worker          10m   v1.31.0

# 2. The other two reasons are on the nodes, not on the pod.
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"  unschedulable="}{.spec.unschedulable}{"  taints="}{.spec.taints}{"\n"}{end}'
# kind-worker   unschedulable=true   taints=
# kind-worker2  unschedulable=       taints=[{dedicated db NoSchedule}]

kubectl describe node kind-worker
#   Spec: ... Unschedulable: true          <- cordoned: takes no new pods
kubectl describe node kind-worker2
#   Taints: dedicated=db:NoSchedule         <- the pod has no toleration for it

# 3. Fix the reasons, on the node you intend to use. There are several
#    correct routes; pick one and make all three conditions hold at once.

# Option A - use the tainted node, which is otherwise healthy:
kubectl taint node kind-worker2 dedicated=db:NoSchedule-
kubectl label node kind-worker2 disk=ssd --overwrite

# Option B - use the cordoned node, which carries no taint:
kubectl uncordon kind-worker
kubectl label node kind-worker disk=ssd --overwrite

# Option C - drop the selector and let the scheduler choose. This only helps
# once one of the two nodes is usable, so you still have to uncordon or
# untaint something first.

# 4. The pod's nodeSelector is immutable, so re-create the pod. Delete the
#    old one first - two pods cannot share the name.
kubectl -n sched delete pod stuck
kubectl -n sched run stuck --image=nginx:1.25 --labels=app=stuck --restart=Never \
  --overrides='{"spec":{"nodeSelector":{"disk":"ssd"}}}'
# (Option C, without the selector:)
# kubectl -n sched run stuck --image=nginx:1.25 --labels=app=stuck --restart=Never

kubectl -n sched wait --for=condition=Ready pod/stuck --timeout=180s

# 5. Say where it landed and what that node looks like.
kubectl -n sched get pod stuck -o wide
# NAME    READY   STATUS    RESTARTS   AGE   IP           NODE
# stuck   1/1     Running   0          30s   10.244.0.7   kind-worker2

kubectl get node kind-worker2 -o jsonpath='{.metadata.name}{"  ready="}{.status.conditions[?(@.type=="Ready")].status}{"  unschedulable="}{.spec.unschedulable}{"  taints="}{.spec.taints}{"\n"}'
# kind-worker2  ready=True  unschedulable=  taints=

# A note on the order of work: uncordon and untaint are node operations and
# survive the Pod being deleted. Give the node the label the selector wants
# BEFORE you re-create the pod, otherwise the new pod will sit Pending again
# with the same event.
