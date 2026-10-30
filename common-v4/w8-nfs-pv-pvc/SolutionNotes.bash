# 1. Read the volume before you write the claim.
#
#    The three things that have to agree are the access modes, the size and
#    the storage class. The volume offers ReadWriteMany and 1Gi, and its
#    storage class is the EMPTY STRING - that last one is the trap.
kubectl get pv pvvol -o yaml

#    A claim that omits storageClassName is defaulted by the API server to
#    the cluster's default class, and then the two do not match. Write it out
#    explicitly, empty string included.

cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc001
  namespace: web
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ""
  resources:
    requests:
      storage: 200Mi
EOF

# 2. Watch it bind. The request is SMALLER than the volume - that is fine, a
#    claim may ask for less than the volume holds. The claim then reports the
#    VOLUME's capacity.
kubectl -n web get pvc pvc001 -w
# NAME      STATUS   VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# pvc001    Bound    pvvol    1Gi        RWO            <none>          2s

kubectl -n web get pvc pvc001 -o jsonpath='{.spec.resources.requests.storage}{" "}{.status.capacity.storage}{" "}{.spec.volumeName}{"\n"}'
# 200Mi 1Gi pvvol

# 3. The Deployment. The claim is mounted where nginx looks for its files.
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: web
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
          image: nginx:1.28
          ports:
            - containerPort: 80
          volumeMounts:
            - name: content
              mountPath: /usr/share/nginx/html
      volumes:
        - name: content
          persistentVolumeClaim:
            claimName: pvc001
EOF

kubectl -n web rollout status deployment/web --timeout=180s

# 4. The Service.
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: web
spec:
  selector:
    app: web
  ports:
    - name: http
      port: 80
      targetPort: 80
      protocol: TCP
EOF

# 5. The live check. This is the point of the question: the file that was
#    ALREADY on the volume has to be served.
kubectl -n web get endpoints web
# NAME   ENDPOINTS     PORT(S)   AGE
# web    10.244.1.7    80/TCP    20s

IP=$(kubectl -n web get svc web -o jsonpath='{.spec.clusterIP}')
curl "http://$IP/"
# <!DOCTYPE html>
# <html>
# <head><title>Hello!</title></head>
# <body>
# <h1>Hello!</h1>
# <p>shared content served from the volume</p>
# </body>
# </html>

# If the ClusterIP is not reachable from where you are sitting, ask a pod
# inside the cluster:
kubectl -n web run curl --rm -i --restart=Never --image=busybox:1.36 -- \
  wget -O- http://web.web.svc.cluster.local/
