# 1. Read the namespace's policy before writing anything.
kubectl -n quota get resourcequota compute-quota -o yaml
# spec:
#   hard:
#     limits.cpu: "2"
#     limits.memory: 4Gi
#     requests.cpu: "2"
#     requests.memory: 4Gi
#
# Every Pod in this namespace has to declare all four of those.

kubectl -n quota get limitrange defaults -o yaml
# spec:
#   limits:
#   - type: Container
#     default:
#       memory: 1Gi
#     defaultRequest:
#       memory: 512Mi
#
# The LimitRange covers memory only, so the CPU values are yours to set.

# 2. Write the Deployment with the resources the quota demands.
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
  namespace: quota
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
        - name: app
          image: nginx:1.25
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
EOF

# 3. Prove it runs.
kubectl -n quota rollout status deployment app --timeout=120s
# deployment "app" successfully rolled out

kubectl -n quota get pods
# NAME                  READY   STATUS    RESTARTS   AGE
# app-6c9f7b8d4d-hq2vp   1/1     Running   0          20s

kubectl -n quota get deploy app -o jsonpath='{.status.readyReplicas}'
# 1

# The second route: declare the CPU values and let the namespace supply the
# memory ones. The LimitRanger merges its defaults into the container per
# resource when the Pod is admitted, so the quota sees all four.
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
  namespace: quota
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
        - name: app
          image: nginx:1.25
          resources:
            requests:
              cpu: 100m
            limits:
              cpu: 500m
EOF

kubectl -n quota get pod -l app=app \
  -o jsonpath='{.items[0].spec.containers[0].resources}'
# {"limits":{"cpu":"500m","memory":"1Gi"},"requests":{"cpu":"100m","memory":"512Mi"}}

# 4. What the refusal looked like, and where it is enforced.
kubectl -n quota describe rs -l app=app
#   Warning  FailedCreate  ...
#   Error creating: pods "app-xxxxx" is forbidden: failed quota: compute-quota:
#   must specify limits.cpu, limits.memory, requests.cpu, requests.memory
#
# The quota is checked by the API server when a Pod is admitted, not by a
# controller afterwards. The Pod is simply refused, so there is never an
# object to look at - the error is the whole of the evidence.
#
# A Deployment with no resources at all is still created; it is the Pod it
# tries to create that is refused, which is why the failure shows up as
# FailedCreate on the ReplicaSet rather than as an error from `kubectl apply`.
