# The Pod: four volumes, four mounts, one container.
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: all-volumes
  namespace: volumes
spec:
  containers:
    - name: app
      image: nginx:1.25
      volumeMounts:
        - name: tmp
          mountPath: /tmp
        - name: cfg
          mountPath: /etc/config
        - name: sec
          mountPath: /etc/secret
        - name: host
          mountPath: /host
  volumes:
    # lives and dies with the Pod
    - name: tmp
      emptyDir: {}
    # one file per key, read-only
    - name: cfg
      configMap:
        name: app-config
    # one file per key, base64-decoded by the kubelet
    - name: sec
      secret:
        secretName: app-secret
    # the node's own filesystem
    - name: host
      hostPath:
        path: /tmp/hostdata
EOF

kubectl -n volumes get pod all-volumes
# NAME          READY   STATUS    RESTARTS   AGE
# all-volumes   1/1     Running   0          12s

# What the mounts actually look like.
kubectl -n volumes exec all-volumes -- ls /etc/config
# nginx.conf
#
kubectl -n volumes exec all-volumes -- ls /etc/secret
# api-key
#
kubectl -n volumes exec all-volumes -- ls /tmp
#
kubectl -n volumes exec all-volumes -- ls /host
# .cka-lab-marker

# The ConfigMap mount shows the key as a file, and it is read-only:
kubectl -n volumes exec all-volumes -- cat /etc/config/nginx.conf
# server {
#   listen 80;
#   ...
#
kubectl -n volumes exec all-volumes -- sh -c 'echo x > /etc/config/nginx.conf'
# sh: can't create /etc/config/nginx.conf: Read-only file system

# The Secret mount shows the decoded value, not the base64:
kubectl -n volumes exec all-volumes -- cat /etc/secret/api-key
# cka-lab-secret-value

# A quicker way to see all four mounts at once:
kubectl -n volumes describe pod all-volumes
# Volumes:
#   tmp    1Gi  /tmp   emptyDir
#   cfg    1Ki  /etc/config  configmap (app-config)
#   sec    1Ki  /etc/secret  secret (app-secret)
#   host   1Gi  /host  host-path /tmp/hostdata
#
# Mounts:
#   /tmp         from tmp   (rw)
#   /etc/config  from cfg   (ro)
#   /etc/secret  from sec   (ro)
#   /host        from host  (rw)
