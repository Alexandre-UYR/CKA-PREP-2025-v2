# 1. Look at what you were given.
kubectl -n stateful get all
# NAME                       READY   UP-TO-DATE   AVAILABLE   AGE
# deployment.apps/web        1/1     1            1           30s
# service/web-headless       1/1     1            1           30s

kubectl -n stateful get svc web-headless -o jsonpath='{.spec.clusterIP}{"\n"}'
# None            <- headless: no cluster IP, so it can hand out per-pod DNS names

kubectl -n stateful get deploy web -o yaml | head -25
# ... a plain Deployment: one replica, labels app=web, no volumes, no identity

# 2. Find the default StorageClass. The claim template has to name a
#    StorageClass that exists, and the task asks for the default one.
kubectl get storageclass
# NAME                PROVISIONER             RECLAIM POLICY   DEFAULT
# standard (default)  rancher.io/local-path   Delete            true

kubectl get storageclass -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}'
# standard

# 3. The Deployment and the StatefulSet cannot both own app=web. Take the
#    Deployment out of the way first.
kubectl -n stateful delete deployment web

# 4. Create the StatefulSet. The claim template is called "web" here, which
#    gives the claims the names web-web-0, web-web-1 and web-web-2.
cat <<'EOF' | kubectl apply -n stateful -f -
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: web
  namespace: stateful
  labels:
    app: web
spec:
  serviceName: web-headless
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: web
          image: nginx:1.25
          ports:
            - name: http
              containerPort: 80
          volumeMounts:
            - name: web
              mountPath: /usr/share/nginx/html
  volumeClaimTemplates:
    - metadata:
        name: web
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 1Gi
        storageClassName: standard
EOF

# 5. Wait for it.
kubectl -n stateful rollout status statefulset/web --timeout=180s
# statefulset/web successfully rolled out

# 6. Three identities...
kubectl -n stateful get pods -o wide
# NAME    READY   STATUS    RESTARTS   AGE   IP           NODE
# web-0   1/1     Running   0          30s   10.244.0.5   kind-worker
# web-1   1/1     Running   0          30s   10.244.0.6   kind-worker
# web-2   1/1     Running   0          30s   10.244.0.7   kind-worker

# ...and three disks.
kubectl -n stateful get pvc
# NAME          STATUS   VOLUME    CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# web-web-0     Bound    pvc-...   1Gi        RWO            standard       30s
# web-web-1     Bound    pvc-...   1Gi        RWO            standard       30s
# web-web-2     Bound    pvc-...   1Gi        RWO            standard       30s

# 7. The stable DNS name each pod got. <podName>.<serviceName>:
kubectl -n stateful run dnscheck --rm -it --image=busybox:1.36 --restart=Never -- \
  nslookup web-1.web-headless
# Server:    10.96.0.10
# Address:   10.96.0.10:53
#
# Name:      web-1.web-headless
# Address:   10.244.0.6

# A note on the names: the StatefulSet gives the pods their identity
# (web-0, web-1, web-2) and the headless Service gives them their DNS name.
# The PVCs are not created by you - the controller creates one per pod from
# the template, and names it <claimTemplateName>-<statefulSetName>-<ordinal>.
