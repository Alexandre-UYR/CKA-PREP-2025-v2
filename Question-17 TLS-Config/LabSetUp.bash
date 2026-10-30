#!/bin/bash
set -e

# Step 1: Create namespace
kubectl create namespace nginx-static || true

# Step 2: Create a TLS secret (self-signed)
# Keep the key material in a scratch directory, not in the working directory.
mkdir -p /tmp/cka-lab
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /tmp/cka-lab/q17.tls.key -out /tmp/cka-lab/q17.tls.crt -subj "/CN=ckaquestion.k8s.local"
# apply (not create) so a second run of the setup does not die on AlreadyExists
kubectl -n nginx-static create secret tls nginx-tls \
  --cert=/tmp/cka-lab/q17.tls.crt --key=/tmp/cka-lab/q17.tls.key \
  --dry-run=client -o yaml | kubectl apply -f -
rm -f /tmp/cka-lab/q17.tls.crt /tmp/cka-lab/q17.tls.key

# Step 3: Create ConfigMap with TLSv1.2 and TLSv1.3 enabled
cat <<EOF | kubectl -n nginx-static apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  nginx.conf: |
    events {}
    http {
      server {
        listen 443 ssl;
        ssl_certificate /etc/nginx/tls/tls.crt;
        ssl_certificate_key /etc/nginx/tls/tls.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        location / {
          return 200 "Hello TLS\n";
        }
      }
    }
EOF

# Step 4: Deploy nginx using the ConfigMap and TLS secret
cat <<EOF | kubectl -n nginx-static apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-static
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-static
  template:
    metadata:
      labels:
        app: nginx-static
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        volumeMounts:
        - name: config
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf
        - name: tls
          mountPath: /etc/nginx/tls
      volumes:
      - name: config
        configMap:
          name: nginx-config
      - name: tls
        secret:
          secretName: nginx-tls
EOF

# Step 5: Create the ClusterIP service the question talks about.
# The question says "There is a service called nginx-service in the nginx-static
# namespace that is currently exposing the deployment", so that is the name it has.
cat <<EOF | kubectl -n nginx-static apply -f -
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: nginx-static
spec:
  type: ClusterIP
  selector:
    app: nginx-static
  ports:
  - name: https
    port: 443
    targetPort: 443
    protocol: TCP
EOF

# Step 6: Record the state the validator compares against.
# The pod's creation timestamp proves the pods were recreated after the ConfigMap
# was edited - editing a ConfigMap does not restart the pods that mount it.
kubectl -n nginx-static rollout status deployment/nginx-static --timeout=180s || true
mkdir -p /tmp/cka-lab
kubectl -n nginx-static get pods -l app=nginx-static -o jsonpath='{.items[0].metadata.creationTimestamp}' \
  > /tmp/cka-lab/q17.pod.before 2>/dev/null || true
date +%s > /tmp/cka-lab/q17.setup.time

echo "nginx TLS lab setup complete."
