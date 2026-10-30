# The namespace and the Secret are already there. What is missing is the
# Deployment that reads the Secret twice.
kubectl -n secrets get secret app-secret
# NAME         TYPE     DATA   AGE
# app-secret   Opaque   2      20s

# 1. The Deployment.
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secret
  namespace: secrets
spec:
  replicas: 1
  selector:
    matchLabels:
      app: secret
  template:
    metadata:
      labels:
        app: secret
    spec:
      containers:
        - name: secret
          image: nginx
          # The environment variables. envFrom imports EVERY key of the
          # Secret, and the variable names are the KEY names: username and
          # password. There is no way to rename them here.
          envFrom:
            - secretRef:
                name: app-secret
          # The files. A Secret mounted as a volume arrives as one file per
          # key, named after the key.
          volumeMounts:
            - name: secret-vol
              mountPath: /etc/secret
              readOnly: true
      volumes:
        - name: secret-vol
          secret:
            secretName: app-secret
EOF

# The equivalent with two explicit env entries, if you would rather have the
# variable names under your own control:
#
#          env:
#            - name: username
#              valueFrom:
#                secretKeyRef:
#                  name: app-secret
#                  key: username
#            - name: password
#              valueFrom:
#                secretKeyRef:
#                  name: app-secret
#                  key: password

kubectl -n secrets rollout status deployment/secret --timeout=120s

# 2. Show it working, from inside the pod.
POD=$(kubectl -n secrets get pod -l app=secret -o jsonpath='{.items[0].metadata.name}')
echo "pod: $POD"

# The variables.
kubectl -n secrets exec "$POD" -- printenv username
# admin
kubectl -n secrets exec "$POD" -- printenv password
# s3cr3t

# The files. One file per key, named after the key, and already decoded.
kubectl -n secrets exec "$POD" -- ls -l /etc/secret
# -rw-r--r-- 1 root root 6 Jan  1 10:00 ..2026_01_01_10_00_00.123456789 username
# -rw-r--r-- 1 root root 7 Jan  1 10:00 ..2026_01_01_10_00_00.123456789 password

kubectl -n secrets exec "$POD" -- cat /etc/secret/username
# admin
kubectl -n secrets exec "$POD" -- cat /etc/secret/password
# s3cr3t
#
# `admin` and `s3cr3t`, not `YWRtaW4=` and `czNjcjN0`: the kubelet decoded
# the base64 for you on the way in.
