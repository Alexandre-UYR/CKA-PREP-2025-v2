# 1. Read the configuration you are meant to use, and note the paths it names.
kubectl -n sec get configmap nginx-conf -o jsonpath='{.data.nginx\.conf}'
#
#   error_log  /tmp/nginx-error.log warn;
#   pid        /var/run/nginx/nginx.pid;
#   client_body_temp_path /tmp/client_temp;
#   proxy_temp_path       /var/cache/nginx/proxy_temp;
#   ...
#
# So nginx writes under /var/run/nginx and /var/cache/nginx. Both of those are
# owned by root in the image, and the task wants a non-root user.

# 2. The Pod's securityContext cannot be changed in place, so the Pod is
#    deleted and re-created with the identity the task asks for.
kubectl -n sec delete pod myuserpod

cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: myuserpod
  namespace: sec
  labels:
    app: nginx
spec:
  securityContext:
    runAsUser: 4242
    runAsGroup: 4242
    fsGroup: 4242
  containers:
    - name: nginx
      image: nginx:1.25
      # The stock configuration listens on 80, which a non-root user cannot
      # bind, so the configuration moves to 8000 - and the ConfigMap already
      # does that.
      ports:
        - containerPort: 8000
      # The image's entrypoint script edits /etc/nginx/conf.d/default.conf,
      # which a non-root user cannot write, so the entrypoint is bypassed and
      # nginx is started directly.
      command: ["nginx", "-g", "daemon off;"]
      volumeMounts:
        - name: nginx-conf
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf
        - name: nginx-cache
          mountPath: /var/cache/nginx
        - name: nginx-run
          mountPath: /var/run/nginx
  volumes:
    - name: nginx-conf
      configMap:
        name: nginx-conf
    # emptyDir volumes are writable by the container's user, so they give
    # nginx the directories it needs.
    - name: nginx-cache
      emptyDir: {}
    - name: nginx-run
      emptyDir: {}
EOF

# 3. Check that it came up.
kubectl -n sec get pod myuserpod
# NAME        READY   STATUS    RESTARTS   AGE
# myuserpod   1/1     Running   0          8s

# 4. Prove it from inside the Pod. The stock configuration listens on 80, so
#    a 200 on 8000 also proves the ConfigMap's configuration is in force.
kubectl -n sec exec myuserpod -- bash -c \
  'exec 3<>/dev/tcp/127.0.0.1/8000 && printf "GET / HTTP/1.0\r\nHost: localhost\r\n\r\n" >&3 && head -n 1 <&3'
# HTTP/1.1 200 OK

# 5. And that the process really is running as 4242.
kubectl -n sec exec myuserpod -- id -u
# 4242
