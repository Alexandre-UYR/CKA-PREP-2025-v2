# 1. Look at the manifest, and at the Service it is supposed to fit.
#
#    cat /tmp/cka-lab/dodgy.yaml
#    kubectl -n dodgy get svc dodgy-svc -o yaml
#
#    The Service's targetPort is 8080. The manifest's container declares
#    containerPort 80. That is one of the three problems.
#
#    The manifest's selector says `app: dodgy`. Its pod template's labels
#    say `app: dodgy-app`. That is another one.
#
#    And there is no `spec.replicas` at all - the API server will quietly
#    default it to 1.

# 2. Fix the FILE. The three changes:
#
#    - spec.selector.matchLabels: app: dodgy  ->  app: dodgy-app
#      (the template's labels are what the Service selects, so the selector
#       is the side that has to move)
#    - containerPort: 80  ->  containerPort: 8080
#    - add `replicas: 2` under spec
#
#    The corrected file:
cat <<'EOF' > /tmp/cka-lab/dodgy.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dodgy-app
  namespace: dodgy
  labels:
    app: dodgy-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: dodgy-app
  template:
    metadata:
      labels:
        app: dodgy-app
    spec:
      containers:
        - name: app
          image: busybox:1.36
          command: ["sh", "-c", "httpd -f -p 8080 -h /tmp"]
          ports:
            - containerPort: 8080
              protocol: TCP
EOF

# 3. Apply it.
kubectl apply -f /tmp/cka-lab/dodgy.yaml
#
#    If you apply the file as it was, the API server refuses it and says
#    exactly what is wrong:
#
#    error: the Deployment "dodgy-app" is invalid: spec.template.metadata.labels:
#      Invalid value: map[string]string{"app":"dodgy-app"}: `selector` does not
#      match template `labels`

kubectl -n dodgy get deploy dodgy-app
# NAME        READY   UP-TO-DATE   AVAILABLE   AGE
# dodgy-app   2/2     2            2           5s

# 4. And the Service finds the pods now.
kubectl -n dodgy get endpoints dodgy-svc
# NAME        ENDPOINTS                           AGE
# dodgy-svc   10.244.2.7:8080,10.244.2.8:8080    6s
#
# The endpoints carry the port from the container's declaration, which is why
# a containerPort that does not match the targetPort leaves the Endpoints
# object empty.

# 5. And it really serves.
kubectl -n dodgy run curl --restart=Never --image=busybox:1.36 -- \
  wget -q -O - -T 5 http://dodgy-svc.dodgy.svc.cluster.local:80/
#
# (a directory listing - the container is busybox's httpd on port 8080)
