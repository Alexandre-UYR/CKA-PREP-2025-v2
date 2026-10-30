# Update the EXISTING Deployment.
#
# The cleanest way to change a live Deployment is to take its manifest, edit
# it, and apply it back:
#
#   kubectl -n sidecar get deploy app -o yaml > app.yaml
#   # ... add the sidecar container, the volume and the two volumeMounts ...
#   kubectl apply -f app.yaml
#
# The manifest below is the finished object.

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
  namespace: sidecar
  labels:
    app: app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app
  template:
    metadata:
      labels:
        app: app
    spec:
      containers:
        - name: nginx
          image: nginx:1.25
          volumeMounts:
            - name: logs
              mountPath: /var/log
        - name: sidecar
          image: busybox:stable
          command:
            - sh
            - -c
            - 'while true; do echo "$(date) app log line" >> /var/log/app.log; sleep 5; done'
          volumeMounts:
            - name: logs
              mountPath: /var/log
      volumes:
        - name: logs
          emptyDir: {}
EOF

# Wait for the new ReplicaSet to roll out. The sidecar has to be running
# before the shared file exists.
kubectl -n sidecar rollout status deploy/app --timeout=120s

# The file lives in the shared emptyDir, so it is visible from either
# container. Check it from the sidecar.
kubectl -n sidecar exec deploy/app -c sidecar -- ls -l /var/log/app.log
# -rw-r--r--    1 root     root             0 Oct 30 17:20 /var/log/app.log

# The same file, seen from the nginx container.
kubectl -n sidecar exec deploy/app -c nginx -- ls -l /var/log/app.log

# A quicker way to see both containers at once:
kubectl -n sidecar get pod -l app=app
# NAME                       READY   STATUS    RESTARTS   AGE
# app-6d8f7c9b4c-xk2vp       2/2     Running   0          25s
#
# The alternative, without a file: a strategic merge patch. Containers are
# merged by name, so the nginx container is left alone and only the sidecar
# is added.
#
#   kubectl -n sidecar patch deploy app --type='strategic' -p '{
#     "spec": {
#       "template": {
#         "spec": {
#           "containers": [{
#             "name": "sidecar",
#             "image": "busybox:stable",
#             "command": ["sh","-c","while true; do echo \"$(date) app log line\" >> /var/log/app.log; sleep 5; done"]
#           }],
#           "volumes": [{"name": "logs", "emptyDir": {}}]
#         }
#       }
#     }
#   }'
#
# ... but a strategic merge patch cannot add the volumeMount to the existing
# nginx container without naming that container too, so the manifest is the
# less fiddly route.
