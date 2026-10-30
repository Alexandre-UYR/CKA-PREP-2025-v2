# 1. Look at what is actually happening.
kubectl -n oom get pods
# NAME                     READY   STATUS             RESTARTS   AGE
# greedy-6c9f7b8d4-x2n7k   0/1     CrashLoopBackOff   3          2m

kubectl -n oom describe pod -l app=greedy
#   Last State:  Terminated
#     Reason:    OOMKilled
#     Exit Code: 137
#
# Exit code 137 is 128 + 9: SIGKILL. The kubelet sends SIGKILL when the
# container's cgroup hits its memory limit.

# The same information, straight from the status:
kubectl -n oom get pod -l app=greedy \
  -o jsonpath='{.items[0].status.containerStatuses[0].lastState.terminated.reason}'
# OOMKilled

# 2. Look at the limit that is killing it.
kubectl -n oom get deploy greedy -o yaml | grep -A4 resources
#         resources:
#           limits:
#             memory: 32Mi
#           requests:
#             memory: 16Mi

# The container tries to hold 100MB in a 32Mi cgroup. That cannot work.

# 3. Give it room - and keep a limit, as the task requires.
kubectl -n oom set resources deployment greedy \
  --requests=memory=64Mi --limits=memory=256Mi

kubectl -n oom rollout status deployment greedy --timeout=120s

# 4. Verify it stays up rather than merely being up right now.
kubectl -n oom get pods
# NAME                     READY   STATUS    RESTARTS   AGE
# greedy-6c9f7b8d4-p8x2m   1/1     Running   0          30s

# The restart count is the thing to watch: if it is still climbing, the
# container is still being killed.
kubectl -n oom get pod -l app=greedy \
  -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}'
# 0

# A note on the request: it is what the scheduler reserves and what the QoS
# class is derived from, so it should rise with the limit rather than stay at
# 16Mi.
