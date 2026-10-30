# 1. Look at the Service, and then at its endpoints.
#
# `kubectl get svc` tells you the Service exists and what it looks like. It
# does NOT tell you whether it points at anything.
kubectl -n svcs get svc
# NAME            TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
# web-clusterip   ClusterIP   10.96.240.14   <none>        80/TCP    40s

kubectl -n svcs get endpoints web-clusterip
# NAME            ENDPOINTS   AGE
# web-clusterip   <none>      40s
#
# The endpoints are the pods the Service's SELECTOR matches. There are none.

# 2. Compare the selector with the pods' labels.
kubectl -n svcs get svc web-clusterip -o jsonpath='{.spec.selector}'
# map[app:web-v2]

kubectl -n svcs get pods --show-labels
# NAME                      READY   STATUS    RESTARTS   AGE   LABELS
# web-6c9f7b8d4-lm4kp       1/1     Running   0          40s   app=web
# web-6c9f7b8d4-q7x2v       1/1     Running   0          40s   app=web
#
# The selector asks for app=web-v2. The pods are labelled app=web. Nothing
# matches, so the Service resolves to nothing.

# 3. Fix it IN PLACE. Patch the selector - do not delete the Service, or it
#    becomes a different object.
kubectl -n svcs patch svc web-clusterip -p '{"spec":{"selector":{"app":"web"}}}'

kubectl -n svcs get endpoints web-clusterip
# NAME            ENDPOINTS                AGE
# web-clusterip   10.244.0.11,10.244.0.12  45s
#
# The endpoints controller takes a second or two to catch up, so give it a
# moment before you check.

# 4. The NodePort Service.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: web-nodeport
  namespace: svcs
spec:
  type: NodePort
  selector:
    app: web
  ports:
    - name: http
      port: 80
      targetPort: 80
      nodePort: 30080
      protocol: TCP
EOF

# 5. The LoadBalancer Service.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: web-lb
  namespace: svcs
spec:
  type: LoadBalancer
  selector:
    app: web
  ports:
    - name: http
      port: 80
      targetPort: 80
      protocol: TCP
EOF

kubectl -n svcs get svc
# NAME            TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
# web-clusterip   ClusterIP      10.96.240.14   <none>        80/TCP         2m
# web-lb          LoadBalancer   10.96.31.20    <pending>     80/TCP         30s
# web-nodeport    NodePort       10.96.108.73   <none>        80:30080/TCP   30s

# The EXTERNAL-IP of web-lb stays <pending> on a cluster with no
# load-balancer implementation. That is the environment, not the answer. What
# matters is that it has endpoints:
kubectl -n svcs get endpoints
# NAME            ENDPOINTS                AGE
# web-clusterip   10.244.0.11,10.244.0.12  2m
# web-lb          10.244.0.11,10.244.0.12  35s
# web-nodeport    10.244.0.11,10.244.0.12  35s

# All three now select the same two pods, and all three have endpoints.

# A one-liner for the whole thing, if you prefer patching to editing:
kubectl -n svcs patch svc web-clusterip -p '{"spec":{"selector":{"app":"web"}}}'
kubectl -n svcs expose deployment web --type=NodePort --port=80 --target-port=80 \
  --name=web-nodeport --selector=app=web
kubectl -n svcs expose deployment web --type=LoadBalancer --port=80 \
  --target-port=80 --name=web-lb --selector=app=web
#
# `kubectl expose` gives you the Service and its selector, but the nodePort
# still has to be set. Some kubectl versions take `--node-port=30080`; where
# they do not, patch the Service afterwards:
#
#   kubectl -n svcs patch svc web-nodeport \
#     -p '{"spec":{"ports":[{"port":80,"targetPort":80,"nodePort":30080,"protocol":"TCP"}]}}'
#
# Applying the manifest above is the simpler route.
