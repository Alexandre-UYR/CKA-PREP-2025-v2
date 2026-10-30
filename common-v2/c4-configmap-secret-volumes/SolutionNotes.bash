# The ConfigMap and the Secret. `--dry-run=client -o yaml | kubectl apply -f -`
# makes both commands safe to re-run.

kubectl -n config create configmap app-config \
  --from-literal=LOG_LEVEL=debug \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n config create secret generic app-secret \
  --from-literal=DB_PASS=s3cret \
  --dry-run=client -o yaml | kubectl apply -f -

# The Deployment uses both of them, twice each: once as a mounted volume and
# once as an injected environment variable.

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
  namespace: config
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
          env:
            - name: LOG_LEVEL
              valueFrom:
                configMapKeyRef:
                  name: app-config
                  key: LOG_LEVEL
            - name: DB_PASS
              valueFrom:
                secretKeyRef:
                  name: app-secret
                  key: DB_PASS
          volumeMounts:
            - name: config
              mountPath: /etc/config
              readOnly: true
            - name: secret
              mountPath: /etc/secret
              readOnly: true
      volumes:
        - name: config
          configMap:
            name: app-config
        - name: secret
          secret:
            secretName: app-secret
EOF

kubectl -n config rollout status deploy/app --timeout=120s

# The file-based route: the key is the file name inside the mount.
kubectl -n config exec deploy/app -- ls -l /etc/config
# -rw-r--r--    1 root     root             5 Oct 30 17:20 LOG_LEVEL

kubectl -n config exec deploy/app -- ls -l /etc/secret
# -rw-r--r--    1 root     root             6 Oct 30 17:20 DB_PASS

# The env var route, checked from inside the container.
kubectl -n config exec deploy/app -- sh -c 'echo "$LOG_LEVEL / $DB_PASS"'
# debug / s3cret

# The Secret is base64-encoded in the stored object, but not in the
# environment of the running container:
kubectl -n config get secret app-secret -o jsonpath='{.data.DB_PASS}' | base64 -d
# s3cret
