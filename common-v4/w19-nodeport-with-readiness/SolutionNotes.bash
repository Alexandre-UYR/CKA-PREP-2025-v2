# 1. The NodePort Service.
#
# nodePort 30080 and port 80 are separate fields: 30080 is the port the node
# opens for traffic from outside the cluster, 80 is the port clients use on
# the Service itself.
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: catalog-svc
  namespace: edge
spec:
  type: NodePort
  selector:
    app: catalog
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30080
      protocol: TCP
EOF

kubectl -n edge get svc catalog-svc
# NAME         TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
# catalog-svc   NodePort   10.96.208.44   <none>        80:30080/TCP   8s

# 2. The readiness probe, on the pod template.
#
# It goes on the template, not on the running pods: the container list of a
# running Pod cannot be changed, but a Deployment rolls out new pods when its
# template changes. So a strategic merge patch on the Deployment is the way to
# do it.
kubectl -n edge patch deployment catalog --type=strategic -p '
spec:
  template:
    spec:
      containers:
        - name: nginx
          readinessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 2
            periodSeconds: 5'

# Wait for the rollout - the new pods start unready until the probe passes.
kubectl -n edge rollout status deployment/catalog --timeout=120s

kubectl -n edge get deploy catalog -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}'
# {"httpGet":{"path":"/","port":80},"initialDelaySeconds":2,"periodSeconds":5}

# 3. The endpoints are the pods the probe has passed.
kubectl -n edge get endpoints catalog-svc
# NAME          ENDPOINTS                                       AGE
# catalog-svc   10.244.1.6:80,10.244.1.7:80                     14s

kubectl -n edge get deploy catalog -o jsonpath='{.status.readyReplicas}'
# 2

# 4. Reach it from inside the cluster.
kubectl -n edge run ck --rm -i --restart=Never --image=busybox:1.36 -- \
  wget -q -O - http://catalog-svc.edge.svc.cluster.local:80/
# "kubectl run --rm -i" needs a terminal; without one, use:
kubectl -n edge run ck --restart=Never --image=busybox:1.36 -- \
  wget -q -O - http://catalog-svc.edge.svc.cluster.local:80/
kubectl -n edge logs ck
# <!DOCTYPE html> ... Welcome to nginx! ...
kubectl -n edge delete pod ck --ignore-not-found

# 5. And reach it from OUTSIDE the cluster, on the node's IP.
NODEIP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "http://$NODEIP:30080"
# Open that in a browser on your laptop: it answers, because a NodePort is
# published on every node. A ClusterIP would not be reachable from there.
