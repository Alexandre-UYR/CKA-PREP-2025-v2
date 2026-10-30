# 1. Look at the cluster before writing anything.
kubectl get nodes -o wide
# NAME               STATUS   ROLES           AGE   VERSION
# cka-control-plane  Ready    control-plane   9d    v1.31.0
# cka-worker-1       Ready    <none>          9d    v1.31.0
# cka-worker-2       Ready    <none>          9d    v1.31.0

kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.taints[*].key}{":"}{.spec.taints[*].effect}{"\n"}{end}'
# cka-control-plane  node-role.kubernetes.io/control-plane:NoSchedule
# cka-worker-1
# cka-worker-2

# The control-plane node is tainted NoSchedule. Nothing lands there unless the
# pod template tolerates the taint - and note the label on the worker nodes:
#
kubectl get nodes -L monitoring
# NAME               ROLES           AGE   VERSION
# cka-control-plane  control-plane   9d    v1.31.0
# cka-worker-1       <none>          9d    v1.31.0
# cka-worker-2       <none>          9d    v1.31.0
#
# monitoring=yes is on exactly one node. A nodeSelector built from it would
# leave the DaemonSet with a single pod. The task says EVERY node.

# 2. Write the DaemonSet.
cat <<'EOF' | kubectl apply -n ds -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: agent
  namespace: ds
  labels:
    app: agent
spec:
  selector:
    matchLabels:
      app: agent
  template:
    metadata:
      labels:
        app: agent
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
      containers:
        - name: agent
          image: busybox:1.36
          command: ["sh", "-c", "sleep 3600"]
EOF

# operator: Exists tolerates the taint whatever value it carries; the taint has
# no value, so operator: Equal with value: "" would do the same. Leaving the
# effect out would tolerate every effect, which is also fine.

# 3. Check the numbers.
kubectl -n ds get ds agent
# NAME    DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
# agent   3         3         3       3            3           <none>           20s

# DESIRED is 3 - the controller wants a pod on every node, the tainted one
# included. READY is 3, which means the pod on the control-plane node was
# tolerated and started.

kubectl -n ds get pods -o wide
# NAME                READY   STATUS    RESTARTS   AGE   NODE              NOMINATED NODE   READINESS GATES
# agent-2x4kt          1/1     Running   0          20s   cka-control-plane   <none>           <none>
# agent-7fh9d          1/1     Running   0          20s   cka-worker-1        <none>           <none>
# agent-qm2zl          1/1     Running   0          20s   cka-worker-2        <none>           <none>

# 4. For comparison, this is what the DaemonSet looks like without the
#    toleration - DESIRED is still 3, but the control-plane pod never starts:
#
#     agent-2x4kt          0/1     Pending   0          20s   cka-control-plane
#       Events: 0/1 nodes (pod had untolerated taint {node-role.kubernetes.io/control-plane: })
#
# That is the symptom the question is about: a pod that exists, and is not
# running, on exactly the node the taint names.
