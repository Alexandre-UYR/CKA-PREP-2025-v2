# 1. Create the StorageClass.
#
# The annotation can be set at creation time. The value is a string, so it has
# to be quoted.
cat <<'EOF' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
EOF

# 2. Take the default flag away from the class that had it. The flag is per
#    cluster: two classes marked default is an ambiguity, not a default.
kubectl get sc -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}'
# local-path true
#
# kubectl patch sc local-path --type=merge \
#   -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
#
# (If the old default should not carry the annotation at all any more, remove
# it instead:
#
#   kubectl annotate sc local-path storageclass.kubernetes.io/is-default-class-
# )

# The same thing in one step, if you would rather not create the class as
# default and patch it afterwards:
#
#   kubectl patch sc fast --type=merge \
#     -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

kubectl get sc
# NAME         PROVISIONER              RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION
# fast         rancher.io/local-path    Delete          WaitForFirstConsumer   false
# local-path   rancher.io/local-path    Delete          Immediate              false

# 3. The claim. It names no StorageClass, so it takes the cluster default.
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data
  namespace: provisioning
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

# 4. The Pod that uses it.
#
# With WaitForFirstConsumer the volume is not provisioned until a pod that
# uses the claim is scheduled, so the claim and the Pod are created together.
# Create the claim on its own and it stays Pending for as long as it takes to
# notice there is no pod waiting for it.
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: writer
  namespace: provisioning
spec:
  containers:
    - name: writer
      image: nginx:1.25
      command: ["sh", "-c", "while true; do date >> /data/line.txt; sleep 5; done"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: data
EOF

# 5. Watch it bind.
kubectl -n provisioning get pvc data --watch
# NAME   STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# data   Bound     pvc-...  1Gi        RWO            fast           30s

kubectl -n provisioning get pod writer
# NAME     READY   STATUS    RESTARTS   AGE
# writer   1/1     Running   0          35s

# The claim picked up the default by itself - it never named a class:
kubectl -n provisioning get pvc data -o jsonpath='{.spec.storageClassName}{"\n"}'
# fast
