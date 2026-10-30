# 1. Look at the two objects.
kubectl -n conflict get limitrange
# NAME       LIMIT TYPE   CREATED
# defaults   Container    2m

kubectl -n conflict describe resourcequota tight
# Name:         tight
# Spec:
#   Hard:
#     limits.cpu:      1
#     limits.memory:   1Gi
#     requests.cpu:    500m
#     requests.memory: 512Mi
# Used:
#   requests.cpu:    0
#   requests.memory: 0

# The LimitRange's DEFAULTS are bigger than the quota's CEILINGS:
#   default        cpu 2     memory 4Gi
#   defaultRequest cpu 1     memory 2Gi
#   quota allows   cpu 500m  memory 512Mi (requests), cpu 1, memory 1Gi (limits)

# 2. Ask the API server what it thinks.
kubectl -n conflict run fits --image=busybox:1.28 --restart=Never
# Error from server (Forbidden): pods "fits" is forbidden: exceeded quota: tight,
# requested: limits.cpu=2, limits.memory=4Gi, requests.cpu=1, requests.memory=2Gi,
# used: requests.cpu=0, requests.memory=0, limited: limits.cpu=1, limits.memory=1Gi,
# requests.cpu=500m, requests.memory=512Mi

# The LimitRanger plugin filled the Pod in with the LimitRange's defaults, and
# the ResourceQuota plugin then refused the result. Nobody asked for 4Gi of
# memory - the namespace did it for them.

# 3. The answer: state the resources explicitly, and keep them inside the
#    quota. Nothing is defaulted when every field is given, so the
#    LimitRange's defaults never come into play.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: fits
  namespace: conflict
spec:
  containers:
    - name: app
      image: busybox:1.28
      command: ["sh", "-c", "sleep 3600"]
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: 500m
          memory: 512Mi
EOF

# pod/fits created

kubectl -n conflict get pod fits
# NAME    READY   STATUS    RESTARTS   AGE
# fits    1/1     Running   0          8s

# 4. The quota's usage now accounts for the Pod.
kubectl -n conflict describe resourcequota tight
# Used:
#   limits.cpu:      500m
#   limits.memory:   512Mi
#   requests.cpu:    100m
#   requests.memory: 128Mi

# 5. The other objects were not touched.
kubectl -n conflict get limitrange defaults -o yaml
kubectl -n conflict get resourcequota tight -o yaml

# Note: stating only the limits would also work. The LimitRanger sets the
# requests to the limits when a container has limits but no requests - so
# limits cpu=500m memory=512Mi gives requests cpu=500m memory=512Mi, which
# still fits. But then the Pod depends on the LimitRange to fill in half of
# its resources, and any request above 500m of CPU would be refused.
