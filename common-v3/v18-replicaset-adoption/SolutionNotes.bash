# 1. Look at what was left behind.
kubectl -n adopt get rs
# NAME       DESIRED   CURRENT   READY   AGE
# web-7d9f4  2         2         2       4m
#
# The ReplicaSet is still there with its two replicas. The Deployment that
# made it is gone - that is what "orphaned" means: the Deployment was
# deleted with --cascade=orphan, so the ReplicaSet and its pods survived
# without an owner.

kubectl -n adopt get pods -o wide
# NAME               READY   STATUS    RESTARTS   AGE
# web-7d9f4-abcde    1/1     Running   0          4m
# web-7d9f4-fghij    1/1     Running   0          4m

kubectl -n adopt get pod web-7d9f4-abcde -o jsonpath='{.metadata.ownerReferences}' && echo
# [{"apiVersion":"apps/v1","blockOwnerDeletion":true,"controller":true,
#   "kind":"ReplicaSet","name":"web-7d9f4","uid":"..."}]
#
# The pods are still controlled by the old ReplicaSet. That is the obstacle:
# a ReplicaSet will not adopt a pod that already has a controller, and it
# will not take one away from another controller.

kubectl -n adopt get rs web-7d9f4 -o jsonpath='{.spec.selector}' && echo
# {"matchLabels":{"app":"web"}}
kubectl -n adopt get pod web-7d9f4-abcde -o jsonpath='{.metadata.labels}' && echo
# {"app":"web","pod-template-hash":"7d9f4"}
#
# So the pods carry app=web, and that is the label a new ReplicaSet has to
# select on.

# 2. Let the old owner go, without taking the pods with it.
#
#    Plain `kubectl delete rs web-7d9f4` would DELETE the two pods (they are
#    its dependents), and the new ReplicaSet would then create two fresh
#    ones - that is replacing, not adopting.
#
#    --cascade=orphan removes the ownerReference from the pods and leaves
#    them running.
kubectl -n adopt delete rs web-7d9f4 --cascade=orphan
# replicaset.apps "web-7d9f4" deleted

kubectl -n adopt get pods
# NAME               READY   STATUS    RESTARTS   AGE
# web-7d9f4-abcde    1/1     Running   0          4m
# web-7d9f4-fghij    1/1     Running   0          4m
#
# The same pods, still Running, now with no controller at all.

# 3. Create the ReplicaSet that adopts them.
cat <<'EOF' | kubectl apply -n adopt -f -
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: web-adopted
  namespace: adopt
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: web
          image: nginx:1.25
          ports:
            - containerPort: 80
EOF
# replicaset.apps/web-adopted created

# 4. Give the controller a moment to claim the orphaned pods, then check.
kubectl -n adopt get pods -o custom-columns=\
'NAME:.metadata.name,PHASE:.status.phase,OWNER:.metadata.ownerReferences[0].name'
# NAME               PHASE     OWNER
# web-7d9f4-abcde    Running   web-adopted
# web-7d9f4-fghij    Running   web-adopted
#
# The pod NAMES still carry the old ReplicaSet's hash: adoption does not
# rename a pod, it only changes who owns it. A pod that had been replaced
# would have a new name and a new UID.

kubectl -n adopt get rs
# NAME          DESIRED   CURRENT   READY   AGE
# web-adopted   2         2         2       20s
#
# Two replicas, two pods, and no extra pods were created: the ReplicaSet
# adopted the two that were already there.

# 5. The pods really are the same objects, not new ones with the same names.
kubectl -n adopt get pod web-7d9f4-abcde -o jsonpath='{.metadata.uid}{"\n"}'
# 6c1f2d3e-...
#
# The UID is the one the pods had before the transfer, which is what
# "adopted, not replaced" means.

# An alternative to `delete rs --cascade=orphan` is to strip the owner
# reference by hand:
#
#   kubectl -n adopt patch pod web-7d9f4-abcde --type=json \
#     -p '[{"op":"remove","path":"/metadata/ownerReferences"}]'
#
# ... but the cascade flag is the tidier way to do it for both pods at once.
