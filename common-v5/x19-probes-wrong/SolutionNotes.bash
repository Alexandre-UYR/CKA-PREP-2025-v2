# 1. Look at the pods.
kubectl -n probe get pods -l app=probed
# NAME                           READY   STATUS    RESTARTS   AGE
# probed-6c9d7f8b54-2xk4p        0/1     Running   0          45s
# probed-6c9d7f8b54-mq7rv        0/1     Running   0          45s
#
# Running, but 0/1 ready. That is the readiness probe failing.

kubectl -n probe describe deployment probed
# ...
#     Readiness Probe:  tcp-socket
#       Port:  8000
#       Period:  5 seconds
#       Failure:  3
#     Liveness Probe:   http-get http://10.244.0.7:80/healthz
#       Initial Delay:  5 seconds
#       Period:         10 seconds
#       Failure:        30
#
# The readiness probe points at port 8000, where nothing is listening. The
# liveness probe points at /healthz, which this server does not serve - it
# answers / and 404s everything else.

# The events on a pod say the same thing:
kubectl -n probe describe pod -l app=probed | grep -i -A3 "Readiness probe failed"
#   Readiness probe failed: dial tcp 10.244.0.7:8000: connect: connection refused

# 2. Check what the server actually serves, so the probe can be pointed at
#    something real. The pod proxy asks the container through the API
#    server, and it needs no extra tool in the image.
POD=$(kubectl -n probe get pods -l app=probed -o jsonpath='{.items[0].metadata.name}')

kubectl get --raw "/api/v1/namespaces/probe/pods/$POD:80/proxy/"
# ok

kubectl get --raw "/api/v1/namespaces/probe/pods/$POD:80/proxy/healthz"
# Error from server (NotFound): the server rejected our request for
# "/api/v1/namespaces/probe/pods/.../proxy/healthz"
#
# So / answers and /healthz does not. That is the path the liveness probe
# has to be moved off.
#
# (From inside the container, if it has a client: `kubectl exec $POD --
# wget -qSO- http://127.0.0.1:80/healthz` says the same thing.)

# 3. Fix both probes ON the running Deployment. The pod template can be
#    edited in place; the Deployment must not be deleted and re-created.
kubectl -n probe edit deployment probed
#
#   spec:
#     template:
#       spec:
#         containers:
#         - name: nginx
#           image: nginx:1.25
#           ...
#           readinessProbe:
#             httpGet:
#               path: /
#               port: 80
#             periodSeconds: 5
#             failureThreshold: 3
#           livenessProbe:
#             httpGet:
#               path: /
#               port: 80
#             initialDelaySeconds: 5
#             periodSeconds: 10
#             failureThreshold: 30
#
# Both probes now point at /, which the server answers with 200.
#
# A tcpSocket probe on port 80 works just as well for the readiness probe:
#
#           readinessProbe:
#             tcpSocket:
#               port: 80
#
# and an exec probe works too, as long as the command succeeds:
#
#           livenessProbe:
#             exec:
#               command: ["cat", "/usr/share/nginx/html/index.html"]

# 4. The template change rolls the Deployment: a new ReplicaSet, new pods.
kubectl -n probe rollout status deployment probed --timeout=180s
# deployment "probed" successfully rolled out

kubectl -n probe get pods -l app=probed
# NAME                           READY   STATUS    RESTARTS   AGE
# probed-7f8b9c6d5-4t9wz         1/1     Running   0          30s
# probed-7f8b9c6d5-lm2qp         1/1     Running   0          30s

# 5. Check the restart count. A pod that is Running but has been restarted
#    is a pod whose liveness probe is still failing.
kubectl -n probe get pods -l app=probed \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.containerStatuses[0].restartCount}{"\n"}{end}'
# probed-7f8b9c6d5-4t9wz 0
# probed-7f8b9c6d5-lm2qp 0

# 6. And the Deployment's own counters.
kubectl -n probe get deployment probed \
  -o jsonpath='{.status.replicas}{" replicas, "}{.status.readyReplicas}{" ready"}{"\n"}'
# 2 replicas, 2 ready

# If the liveness probe is still wrong, the pods will look fine for five
# minutes and then start restarting. Watch it for a while:
kubectl -n probe get pods -l app=probed -w
