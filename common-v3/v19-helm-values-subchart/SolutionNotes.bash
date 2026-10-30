# 1. Read the chart before you change anything. Start with what the parent
#    chart's values look like, and where the subchart sits.
cat /tmp/cka-lab/charts/stack/values.yaml
# frontend:
#   image:
#     repository: nginx
#     tag: "1.0.0"
#   replicas: 1
#   service:
#     port: 80
#
# backend:
#   image:
#     repository: nginx
#     tag: "1.0.0"
#   replicas: 1
#   service:
#     port: 8080

cat /tmp/cka-lab/charts/stack/Chart.yaml
# apiVersion: v2
# name: stack
# version: 1.0.0
# dependencies:
#   - name: backend
#     version: 0.1.0
#     repository: "file://charts/backend"

ls /tmp/cka-lab/charts/stack/charts
# backend
#
# The subchart is vendored under charts/, so the chart renders offline and
# `helm dependency update` is not needed to make the subchart appear.

# 2. Write the values file. The backend is a subchart, so its values go
#    under the subchart's own key, `backend:`.
cat > /tmp/cka-lab/stack-values.yaml <<'EOF'
frontend:
  image:
    tag: "2.1.0"
  replicas: 3

backend:
  image:
    tag: "2.0.5"
  replicas: 2
  service:
    port: 9090
EOF

# 3. Check what it renders BEFORE installing anything. helm template does
#    not touch the cluster.
helm template stack /tmp/cka-lab/charts/stack -f /tmp/cka-lab/stack-values.yaml
# ...
# kind: Deployment
# metadata:
#   name: backend
# spec:
#   replicas: 2
#       - name: backend
#         image: "nginx:2.0.5"
# ...
# kind: Service
# metadata:
#   name: backend
# spec:
#   ports:
#     - port: 9090
# ...
# kind: Deployment
# metadata:
#   name: frontend
# spec:
#   replicas: 3
#       - name: frontend
#         image: "nginx:2.1.0"

# 4. Create the namespace, then install the release with the values file.
kubectl create namespace apps

helm install stack /tmp/cka-lab/charts/stack \
  -n apps \
  -f /tmp/cka-lab/stack-values.yaml
# NAME: stack
# NAMESPACE: apps
# STATUS: deployed
# REVISION: 1

# 5. Check the release.
helm list -n apps
# NAME    NAMESPACE  REVISION  UPDATED  STATUS    CHART       APP VERSION
# stack   apps       1         ...      deployed stack-1.0.0 1.0.0

kubectl -n apps get deploy
# NAME       READY   UP-TO-DATE   AVAILABLE   AGE
# backend    1/1     1            1           10s
# frontend   3/3     3            3           10s

kubectl -n apps get svc
# NAME       TYPE        CLUSTER-IP      PORT(S)    AGE
# backend    ClusterIP   10.96.142.18    9090/TCP   10s
# frontend   ClusterIP   10.96.31.204    80/TCP    10s

# The same answer can be given on the command line, but then the values file
# is not the answer:
#
#   helm install stack /tmp/cka-lab/charts/stack -n apps \
#     --set frontend.image.tag=2.1.0 --set frontend.replicas=3 \
#     --set backend.image.tag=2.0.5 --set backend.replicas=2 \
#     --set backend.service.port=9090
#
# Note the prefixes: `backend.` for the subchart, nothing for the parent.
# `--set replicas=2` on its own would set a `replicas` key at the top level
# of the PARENT chart, which has no such key - the backend would still be
# rendered with one replica.
