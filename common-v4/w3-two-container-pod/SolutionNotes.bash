# The example: one container.
kubectl -n multi get pods -o wide
# NAME                   READY   STATUS    RESTARTS   AGE   IP            NODE
# single-6c9f7b8d4-x8p2k 1/1     Running   0          30s   10.244.0.15   kind-worker
#
# The Pod you are asked for has two containers in the same spec, under
# spec.containers. Both commands have to be long-running, because a Pod with
# two containers is restarted as a whole when one of them exits.

# 1. The Pod.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: multi-pod
  namespace: multi
  labels:
    env: test
spec:
  containers:
    - name: busy1
      image: busybox:1.36
      command: ["sleep", "100000"]
    - name: busy2
      image: busybox:1.36
      command: ["sleep", "100000"]
EOF

# 2. Check it.
kubectl -n multi get pod multi-pod
# NAME        READY   STATUS    RESTARTS   AGE
# multi-pod   2/2     Running   0          15s
#
# READY 2/2 - both containers are ready. RESTARTS 0 - nothing has been
# restarted, so neither command has exited.

# 3. Read the commands back out of the spec, which is where the grader reads
#    them from.
kubectl -n multi get pod multi-pod \
  -o jsonpath='{range .spec.containers[*]}{.name}{" -> "}{.command}{"\n"}{end}'
# busy1 -> [sleep 100000]
# busy2 -> [sleep 100000]

# `sleep 100000` is about 27 hours, so the Pod is comfortably still up five
# minutes later. `sleep 100` would be up when you looked at it and gone long
# before the five minutes were out - and because both containers share one
# lifecycle, the second one going would take the first one down with it.

# If you prefer the imperative form, `kubectl run` will get you the shape of
# a single-container Pod:
#
#   kubectl -n multi run multi-pod --image=busybox:1.36 --labels env=test \
#     --restart=Never --command -- sleep 100000
#
# But `kubectl run` only ever makes ONE container, and you cannot ADD a
# second container to a Pod that already exists - the API server refuses
# that change. So the manifest above is the route to take; if you did create
# it with `kubectl run`, delete the Pod and create it again from the
# manifest.
