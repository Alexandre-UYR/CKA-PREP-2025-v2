# Find the node by its label. The name is not written into the manifest: the
# label is the handle that survives being moved to another cluster.
NODE=$(kubectl get nodes -l workload=general -o jsonpath='{.items[0].metadata.name}')
echo "$NODE"

# `pinned` - nodeName names the node outright. The scheduler is not
# consulted at all: the kubelet is told where to run the pod and runs it
# there, taints and all.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pinned
  namespace: place
spec:
  nodeName: $NODE
  containers:
    - name: app
      image: nginx:1.25
EOF

# `selected` - a nodeSelector goes through the scheduler. It has to match a
# node that is Ready, untainted as far as this pod is concerned, and has
# room. The pod label app=selected is what `together`'s affinity will look
# for later.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: selected
  namespace: place
  labels:
    app: selected
spec:
  nodeSelector:
    workload: general
  containers:
    - name: app
      image: nginx:1.25
EOF

# Wait for `selected` to be Running before creating `together`: required pod
# affinity has to find a pod that already satisfies it.
kubectl -n place wait --for=condition=Ready pod/selected --timeout=120s

# `together` - required pod affinity. The labelSelector matches the LABELS
# OF OTHER PODS (app=selected), and the topologyKey says what "the same
# place" means: kubernetes.io/hostname, the same node.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: together
  namespace: place
spec:
  affinity:
    podAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        labelSelector:
          matchLabels:
            app: selected
        topologyKey: kubernetes.io/hostname
  containers:
    - name: app
      image: nginx:1.25
EOF

kubectl -n place get pods -o wide
# NAME       READY   STATUS    RESTARTS   AGE   NODE
# pinned     1/1     Running   0          10s   node-2
# selected   1/1     Running   0          10s   node-2
# together   1/1     Running   0          10s   node-2
#
# All three on the node labelled workload=general - one by name, one by
# selector, one by affinity.
