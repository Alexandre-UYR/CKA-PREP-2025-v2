# 1. Look at what is wrong.
kubectl -n init get pods
# NAME                  READY   STATUS             RESTARTS   AGE
# cfg-6d5b9c7f8b-t4xkq   0/1     CrashLoopBackOff   3          2m

kubectl -n init logs deploy/cfg
# cat: /etc/app/config.yaml: No such file or directory

# The file the app reads does not exist, and nothing produces it.
kubectl -n init get deploy cfg -o yaml | grep -A3 -E 'volumes|initContainers'
# (nothing: no volumes, no init containers)

# The value itself is already in the cluster:
kubectl -n init get configmap app-config -o yaml
# data:
#   config.yaml: |
#     mode: production

# 2. The fix: an init container that copies the ConfigMap's key into a shared
#    emptyDir, and a main container that mounts that same emptyDir.
#
#   kubectl -n init edit deploy cfg
#
#   spec:
#     template:
#       spec:
#         volumes:
#         - name: config-volume
#           configMap:
#             name: app-config
#         - name: shared-config
#           emptyDir: {}
#         initContainers:
#         - name: init-config
#           image: busybox:1.36
#           command:
#           - sh
#           - -c
#           - cp /config-source/config.yaml /etc/app/config.yaml
#           volumeMounts:
#           - name: config-volume
#             mountPath: /config-source
#             readOnly: true
#           - name: shared-config
#             mountPath: /etc/app
#         containers:
#         - name: app
#           image: nginx:1.25
#           command:
#           - sh
#           - -c
#           - cat /etc/app/config.yaml && sleep 3600
#           volumeMounts:
#           - name: shared-config
#             mountPath: /etc/app
#           - name: config-volume
#             mountPath: /etc/config
#             readOnly: true
#
# Note the two mount paths in the main container: the emptyDir at /etc/app
# (where the file must appear) and the ConfigMap somewhere else (/etc/config).
# The same path cannot carry both volumes.

# 3. Check it.
kubectl -n init rollout status deployment cfg --timeout=120s

kubectl -n init get pod -l app=cfg
# NAME                  READY   STATUS    RESTARTS   AGE
# cfg-6d5b9c7f8b-p9m2q   1/1     Running   0          25s

kubectl -n init exec deploy/cfg -- cat /etc/app/config.yaml
# mode: production

# 4. Why the emptyDir is the point.
#
# The init container writes /etc/app/config.yaml into the shared volume. If it
# had written it into its own filesystem instead (no shared-config mount, just
# "cp /config-source/config.yaml /config.yaml"), the init container would
# report success and the main container would still crash: the file died with
# the init container.
