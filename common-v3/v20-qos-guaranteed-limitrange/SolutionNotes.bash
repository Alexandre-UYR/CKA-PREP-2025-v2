# 1. Read the QoS class off the pod - it lives on the pod, not the Deployment.
kubectl -n qos get pod -l app=mixed -o jsonpath='{.items[0].status.qosClass}'
# Burstable

# 2. Look at the Deployment's template. It is not the whole story.
kubectl -n qos get deploy mixed -o yaml | grep -A8 'resources:'
#         resources:
#           limits:
#             cpu: 200m
#             memory: 256Mi
#
# No requests at all - not for 'app', and 'init' has no resources block
# whatsoever. The requests the pod is running with are not in this manifest.

# 3. Find the thing that filled them in: the LimitRange.
kubectl -n qos get limitrange defaults -o yaml
#   limits:
#   - type: Container
#     default:                     # used when a container sets no limits
#       cpu: 100m
#       memory: 128Mi
#     defaultRequest:              # used when a container sets no requests
#       cpu: 50m
#       memory: 64Mi

# The LimitRanger admission plugin applied those at pod creation time. The pod
# therefore has requests, but they are smaller than the limits - which is
# exactly what "Burstable" means. Look at the pod to see it:
kubectl -n qos get pod -l app=mixed -o jsonpath='{.items[0].spec}'
#   containers:
#   - name: app
#     resources:
#       limits:   {cpu: 200m, memory: 256Mi}
#       requests: {cpu: 50m,  memory: 64Mi}     <- injected by the LimitRange
#   initContainers:
#   - name: init
#     resources:
#       limits:   {cpu: 100m, memory: 128Mi}     <- injected by the LimitRange
#       requests: {cpu: 50m,  memory: 64Mi}      <- injected by the LimitRange

# 4. Fix it: every container, the init one included, must set requests equal
#    to its limits. A strategic merge patch merges the container lists by
#    name, so the image and the command survive the patch.
kubectl -n qos patch deployment mixed --type=strategic -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [
          { "name": "app",
            "resources": {
              "requests": { "cpu": "200m", "memory": "256Mi" },
              "limits":   { "cpu": "200m", "memory": "256Mi" } } }
        ],
        "initContainers": [
          { "name": "init",
            "resources": {
              "requests": { "cpu": "50m", "memory": "64Mi" },
              "limits":   { "cpu": "50m", "memory": "64Mi" } } }
        ]
      }
    }
  }
}'

kubectl -n qos rollout status deployment mixed --timeout=120s

# The init container stays comfortably below the main one: 50m/64Mi against
# 200m/256Mi. The values themselves do not have to match - only each
# container's own request and limit have to be equal.

# 5. Verify.
kubectl -n qos get pod -l app=mixed -o jsonpath='{.items[0].status.qosClass}'
# Guaranteed

kubectl -n qos get pod -l app=mixed \
  -o jsonpath='{range .items[*].spec.initContainers[*]}{.name} req={.resources.requests} lim={.resources.limits}{"\n"}{end}'
# init req={cpu:50m,memory:64Mi} lim={cpu:50m,memory:64Mi}

# `kubectl set resources` can do the main container on its own:
#   kubectl -n qos set resources deployment mixed \
#     --containers=app --requests=cpu=200m,memory=256Mi --limits=cpu=200m,memory=256Mi
# but it does not reach the init containers, which are the ones that matter
# here - hence the patch.
