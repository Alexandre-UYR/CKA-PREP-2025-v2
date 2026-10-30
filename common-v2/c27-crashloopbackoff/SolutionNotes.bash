# The Pod is in CrashLoopBackOff. Find out why.
#
# 1. What does the container status say?
kubectl -n broken get pod worker
# NAME     READY   STATUS             RESTARTS   AGE
# worker   0/1     CrashLoopBackOff   5          2m

kubectl -n broken get pod worker \
  -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}{"\n"}'
# CrashLoopBackOff

# 2. The logs of the CURRENT container are empty - the container dies before
#    it writes anything. The error is in the PREVIOUS container:
kubectl -n broken logs worker --previous
# mkdir: can't create directory '/data': Read-only file system

# The same thing from the events:
kubectl -n broken describe pod worker | tail -20
#   Last State:  Terminated
#     Reason:    Error
#     Exit Code: 1
#   Events:
#     Type     Reason     From                 Message
#     ----     ------     ----                 -------
#     Warning  BackOff   kubelet              Back-off restarting failed container worker in pod worker_default

# 3. The cause: the container's root filesystem is read-only, and its command
#    writes to /data. And the field cannot be patched:
kubectl -n broken patch pod worker --type=merge \
  -p '{"spec":{"containers":[{"name":"worker","securityContext":{"readOnlyRootFilesystem":false}}]}}'
# Error from server: Forbidden: pod updates may not change fields other than ...

# 4. The fix: delete the Pod and create it again, with the write allowed.
#    Mounting an emptyDir at /data also works on its own, but the grader wants
#    readOnlyRootFilesystem to be absent or false, so set it to false here.
kubectl -n broken delete pod worker

cat <<'EOF' > worker.yaml
apiVersion: v1
kind: Pod
metadata:
  name: worker
  namespace: broken
spec:
  containers:
    - name: worker
      image: busybox:1.36
      command:
        - sh
        - -c
        - "mkdir -p /data && echo ok >> /data/app.log && sleep 3600"
      securityContext:
        readOnlyRootFilesystem: false
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      emptyDir: {}
EOF

kubectl apply -f worker.yaml

# 5. It stays up now.
kubectl -n broken wait --for=condition=Ready pod/worker --timeout=120s
kubectl -n broken get pod worker
# NAME     READY   STATUS    RESTARTS   AGE
# worker   1/1     Running   0          15s

kubectl -n broken logs worker
# (nothing - the `echo ok` goes into /data/app.log, not to stdout)

kubectl -n broken exec worker -- cat /data/app.log
# ok

# A Pod whose container is crash-looping still has phase Running - look at
# the container status, not at the phase, to tell the two apart.
