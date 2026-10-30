# Two objects to write: the Deployment (with a named container port) and the
# Service (whose targetPort names that port).

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: namedport
  labels:
    app: web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: nginx
          image: nginx:1.25
          ports:
            - name: http
              containerPort: 80
              protocol: TCP
EOF

cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: web-svc
  namespace: namedport
spec:
  type: ClusterIP
  selector:
    app: web
  ports:
    - name: http
      port: 80
      targetPort: http
      protocol: TCP
EOF

# Wait for the pod, or the Endpoint controller has nothing to publish yet.
kubectl -n namedport rollout status deploy/web --timeout=120s

# The Service looks right:
kubectl -n namedport get svc web-svc
# NAME      TYPE        CLUSTER-IP      PORT(S)    AGE
# web-svc   ClusterIP   10.96.141.29    80/TCP     20s

# ... and it really selects the pods:
kubectl -n namedport get endpoints web-svc
# NAME      ENDPOINTS   PORTS   AGE
# web-svc   10.244.0.9  80/TCP  25s

# The name is the whole point. Check that targetPort is the STRING "http"
# and not the number 80:
kubectl -n namedport get svc web-svc -o jsonpath='{.spec.ports[0].targetPort}'
# http

# A quicker way to write the Deployment half, if you would rather patch it:
#
#   kubectl -n namedport patch deploy web --type='strategic' -p '{
#     "spec": {"template": {"spec": {"containers": [{
#       "name": "nginx",
#       "ports": [{"name": "http", "containerPort": 80, "protocol": "TCP"}]
#     }]}}}
#   }'
#
# The container is merged by name, so the ports list is added to the existing
# nginx container rather than replacing it.
