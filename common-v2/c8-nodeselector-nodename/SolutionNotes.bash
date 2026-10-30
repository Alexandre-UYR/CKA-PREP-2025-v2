# The reference answer for c8.
#
# The node is looked up by its label, never written down by hand: node names
# are different in every cluster.

NS=scheduling
NODE=$(kubectl get nodes -l workload=general -o jsonpath='{.items[0].metadata.name}')
echo "node labelled workload=general: $NODE"

# ---- 1. the Pod pinned with nodeName ----
#
# nodeName is set by hand, so the Pod is written out as a manifest.

cat <<EOF > pinned.yaml
apiVersion: v1
kind: Pod
metadata:
  name: pinned
  namespace: $NS
spec:
  nodeName: $NODE
  containers:
    - name: app
      image: nginx:1.25
EOF

kubectl apply -f pinned.yaml

# ---- 2. the Pod pinned with a nodeSelector ----
#
# A nodeSelector is an ordinary scheduling requirement, so the scheduler
# places this one on the same node.

cat <<'EOF' > selected.yaml
apiVersion: v1
kind: Pod
metadata:
  name: selected
  namespace: scheduling
spec:
  nodeSelector:
    workload: general
  containers:
    - name: app
      image: nginx:1.25
EOF

kubectl apply -f selected.yaml

# Both have to be up.
kubectl -n scheduling wait --for=condition=Ready pod/pinned --timeout=120s
kubectl -n scheduling wait --for=condition=Ready pod/selected --timeout=120s

kubectl -n scheduling get pod pinned selected -o wide
# NAME       READY   STATUS    RESTARTS   AGE   IP            NODE
# pinned     1/1     Running   0          8s    10.244.1.5    worker-2
# selected   1/1     Running   0          8s    10.244.2.7    worker-2

# The two mechanisms, seen from the spec:
kubectl -n scheduling get pod pinned -o jsonpath='{.spec.nodeName}{"\n"}'
# worker-2
kubectl -n scheduling get pod selected -o jsonpath='{.spec.nodeSelector}{"\n"}'
# {"workload":"general"}

# A quicker way to write the first Pod, if you would rather not write YAML:
#
#   kubectl -n scheduling run pinned --image=nginx:1.25 \
#     --overrides='{"spec":{"nodeName":"'"$NODE"'"}}'
#
# and for the second:
#
#   kubectl -n scheduling run selected --image=nginx:1.25 \
#     --overrides='{"spec":{"nodeSelector":{"workload":"general"}}}'
#
# Note the difference in what happens if the node cannot take the Pod:
# the nodeName Pod is started by the kubelet anyway, the nodeSelector Pod
# stays Pending, because the scheduler was the one that had to say no.
