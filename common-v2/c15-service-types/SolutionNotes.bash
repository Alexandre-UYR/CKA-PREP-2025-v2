# Three Services, one Deployment.
#
# All three carry the same selector, so all three end up with the same
# endpoints: the nginx pods behind the `web` Deployment.

cat <<'EOF' > services.yaml
apiVersion: v1
kind: Service
metadata:
  name: web-clusterip
  namespace: svctypes
spec:
  type: ClusterIP
  selector:
    app: web
  ports:
    - name: http
      port: 80
      targetPort: 80
      protocol: TCP
---
apiVersion: v1
kind: Service
metadata:
  name: web-nodeport
  namespace: svctypes
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
---
apiVersion: v1
kind: Service
metadata:
  name: web-loadbalancer
  namespace: svctypes
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

kubectl apply -f services.yaml

# What the cluster made of them:
kubectl -n svctypes get svc
# NAME               TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
# web-clusterip      ClusterIP      10.96.142.11   <none>        80/TCP         6s
# web-loadbalancer   LoadBalancer   10.96.201.14   <pending>     80/TCP         6s
# web-nodeport       NodePort       10.96.163.29   <none>        80:30080/TCP   6s

# All three have endpoints - this is the check that the selector matches:
kubectl -n svctypes get endpoints
# NAME                ENDPOINTS   AGE
# web-clusterip       10.244.1.7   8s
# web-loadbalancer    10.244.1.7   8s
# web-nodeport        10.244.1.7   8s

# On a cluster with no load balancer, web-loadbalancer keeps <pending> for
# EXTERNAL-IP. That is expected: nothing implements a load balancer there.
# The Service itself is correct - it has the right type, port and endpoints.

# Reach the Service in-cluster through its cluster IP or its DNS name:
kubectl -n svctypes run curl --rm -i --restart=Never --image=curlimages/curl -- \
  curl -s -m 5 -o /dev/null -w "%{http_code}\n" http://web-clusterip.svctypes.svc.cluster.local
# 200

# Reach the NodePort Service through any node's IP:
kubectl -n svctypes get nodes -o wide
kubectl -n svctypes run curl --rm -i --restart=Never --image=curlimages/curl -- \
  curl -s -m 5 -o /dev/null -w "%{http_code}\n" http://<node-ip>:30080
# 200
