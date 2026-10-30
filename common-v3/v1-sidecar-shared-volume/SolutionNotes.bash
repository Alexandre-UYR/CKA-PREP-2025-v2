# 1. Look at what is there.
kubectl -n sidecar get deploy web -o yaml
#         containers:
#         - name: app
#           image: nginx:1.25
#           command:
#           - sh
#           - -c
#           - |
#             while true; do echo "$(date) app log line" >> /var/log/app.log; sleep 5; done
#
# No volumes. No volumeMounts. Which means /var/log/app.log is a file inside
# the container's writable layer: private to that container, and gone the
# moment the container is recreated.

# Confirm it from the outside:
kubectl -n sidecar exec deploy/web -c app -- cat /var/log/app.log
# 2026-10-30 11:04:12 app log line
# ...
#
# There is no second container to read it from, and no other pod can reach
# into this one.

# 2. The fix: a shared emptyDir mounted at /var/log in BOTH containers, and a
#    sidecar that tails the file.
#
#   kubectl -n sidecar edit deploy web
#
#   spec:
#     template:
#       spec:
#         volumes:
#         - name: shared-logs
#           emptyDir: {}
#         containers:
#         - name: app
#           image: nginx:1.25
#           command:
#           - sh
#           - -c
#           - |
#             while true; do echo "$(date) app log line" >> /var/log/app.log; sleep 5; done
#           volumeMounts:
#           - name: shared-logs
#             mountPath: /var/log
#         - name: logreader
#           image: busybox:1.36
#           command:
#           - sh
#           - -c
#           - |
#             while [ ! -f /var/log/app.log ]; do sleep 1; done; tail -f /var/log/app.log
#           volumeMounts:
#           - name: shared-logs
#             mountPath: /var/log
#
# The wait loop matters: the two containers start at the same time, and the
# app may not have created the file yet when the sidecar first runs. Without
# it, tail exits immediately, the sidecar restarts, and the pod never reaches
# one ready replica.

# 3. Check that the log is really shared, not just that the YAML says so.
kubectl -n sidecar rollout status deployment web --timeout=120s

kubectl -n sidecar exec deploy/web -c logreader -- cat /var/log/app.log
# 2026-10-30 11:04:12 app log line
# 2026-10-30 11:04:17 app log line
#
# Those lines are the app's, and the app is writing them into the emptyDir.

kubectl -n sidecar get deploy web
# NAME   READY   UP-TO-DATE   AVAILABLE   AGE
# web    1/1     1            1           30s

# 4. Why it survives a restart: the emptyDir belongs to the pod, so the file
#    outlives a container restart. Killing the container proves it:
#
# kubectl -n sidecar exec deploy/web -c app -- kill 1
# kubectl -n sidecar exec deploy/web -c logreader -- cat /var/log/app.log
#
# The old lines are still there, and the app keeps appending to the same file.
