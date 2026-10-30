# 1. Look at what you have.
kubectl -n sidecars get deploy legacy -o yaml
#   spec:
#     template:
#       spec:
#         containers:
#         - name: app
#           image: nginx:1.25
#           ...
#         - name: logcollector        <-- a regular container: the legacy pattern
#           image: busybox:1.36
#           command: ["sh","-c","tail -f /var/log/app.log"]
#         volumes:
#         - name: shared-logs
#           emptyDir: {}

# The logcollector is one of the regular containers. It starts alongside the
# app, in an unspecified order, and it is not a sidecar.

# 2. Move it into spec.initContainers and give it restartPolicy: Always.
#    The container block is copied over unchanged - same image, same command,
#    same volume mount - and the original is removed from spec.containers.
kubectl -n sidecars patch deploy legacy --type=json -p='[
  {"op":"remove","path":"/spec/template/spec/containers/1"},
  {"op":"add","path":"/spec/template/spec/initContainers","value":[
    {"name":"logcollector",
     "image":"busybox:1.36",
     "command":["sh","-c","tail -f /var/log/app.log"],
     "volumeMounts":[{"name":"shared-logs","mountPath":"/var/log"}],
     "restartPolicy":"Always"}
  ]}
]'

# 3. Check the result.
kubectl -n sidecars get deploy legacy -o jsonpath='{.spec.template.spec.initContainers}'
# [{"command":["sh","-c","tail -f /var/log/app.log"],"image":"busybox:1.36","name":"logcollector","restartPolicy":"Always","volumeMounts":[{"mountPath":"/var/log","name":"shared-logs"}]}]

kubectl -n sidecars get deploy legacy -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{"\n"}{end}'
# app

# 4. Wait for the rollout and confirm both containers are up.
kubectl -n sidecars rollout status deployment legacy --timeout=120s

kubectl -n sidecars get pods
# NAME                      READY   STATUS    RESTARTS   AGE
# legacy-6c9f7b8d4d-hq2vp    2/2     Running   0          30s

# 5. The running pod is the native one.
kubectl -n sidecars get pod -l app=legacy \
  -o jsonpath='{.items[0].spec.initContainers[?(@.name=="logcollector")].restartPolicy}'
# Always

# A full rewrite with kubectl apply works just as well - the point is that
# the logcollector ends up in spec.initContainers with restartPolicy: Always,
# and that spec.containers is left holding only the app container.
#
# What the native sidecar buys you, in order:
#   - it is started, and is considered STARTED, before the next init
#     container and before the main containers run, so the app never writes
#     into the shared volume before the collector is listening;
#   - it is restarted on its own if it crashes, without the pod going down;
#   - it keeps running for the life of the pod, and is terminated
#     automatically once the pod's main containers have finished.
