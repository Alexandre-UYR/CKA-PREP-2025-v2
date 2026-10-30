# 1. Look at what is killing it.
kubectl -n probe get pods
# NAME                    READY   STATUS    RESTARTS   AGE
# slow-7c9f8b6d5f-4k2xp   0/1     Running   4          2m

kubectl -n probe describe pod -l app=slow | grep -A6 Liveness
#   Liveness:  http-get http://10.244.0.9:8080/health
#     Initial Delay: 5s
#     Timeout: 1s
#     Period: 5s
#     # Failure: 3
#
# The container is `sleep 60; sleep 3600`. Nothing listens on 8080, so every
# probe fails: 5s initial delay, then three failures 5 seconds apart, and
# the kubelet kills the container about 15 seconds in - half way through the
# application's 60-second start-up. It never gets there.

# 2. The fix: a startup probe with a budget that covers the start-up, and a
#    liveness probe that no longer kills an application with nothing to
#    serve.
#
# The application has to publish something the probe can see, so the command
# leaves a marker file the moment it is up, and both probes exec against it.
#
#   kubectl -n probe edit deploy slow
#
#   spec:
#     template:
#       spec:
#         containers:
#         - name: app
#           image: busybox:1.36
#           command:
#           - sh
#           - -c
#           - |
#             sleep 60; touch /tmp/ready; sleep 3600
#           startupProbe:
#             exec:
#               command: ["sh", "-c", "test -f /tmp/ready"]
#             periodSeconds: 5
#             failureThreshold: 15      # 15 x 5 = 75s of budget
#           livenessProbe:
#             exec:
#               command: ["sh", "-c", "test -f /tmp/ready"]
#             periodSeconds: 10
#             failureThreshold: 6
#
# The startup probe's budget is failureThreshold x periodSeconds = 15 x 5 =
# 75 seconds. That is what the kubelet allows the application before it
# gives up and restarts the container. 60 would have been exactly enough;
# give it some slack.
#
# The liveness probe has to change too. While the startup probe is pending
# the liveness probe is not evaluated at all - but the moment the startup
# probe succeeds, the old httpGet on 8080 starts failing again and kills the
# container a quarter of a minute later. Replacing it with an exec probe
# against the same marker makes it mean something.

# 3. Check it.
kubectl -n probe rollout status deployment slow --timeout=180s

kubectl -n probe get pod -l app=slow
# NAME                    READY   STATUS    RESTARTS   AGE
# slow-7c9f8b6d5f-pq7dn   1/1     Running   0          80s
#
# The pod is Ready, and the restart count is 0: it did not restart once.
# The Ready state comes from the startup probe - until it succeeds, the
# container is not ready even though it is running.

# 4. Watch it stay up. The restart count is the thing to watch.
kubectl -n probe get pod -l app=slow \
  -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}'
# 0
#
# ...and again, ten seconds later.
# 0

# An alternative that needs no marker file: keep the command untouched and
# have the startup probe detect the finished start-up by looking for the
# long sleep in the container's process list.
#
#   startupProbe:
#     exec:
#       command:
#       - sh
#       - -c
#       - "cat /proc/[0-9]*/cmdline 2>/dev/null | tr '\\0' ' ' | grep -q 'sleep 3600'"
#     periodSeconds: 5
#     failureThreshold: 15
#
# The liveness probe still has to stop polling the port nothing listens on.
