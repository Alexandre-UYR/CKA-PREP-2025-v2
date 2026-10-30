# The Service. Written out as a manifest because three of its fields have to
# be right and it is easier to see them all at once than to patch them in.
#
#   port: 8080        - what clients connect to
#   name: http        - the Service's port has to be named
#   targetPort: http  - the NAME of the container's port, which is 80
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: site-svc
  namespace: web
spec:
  selector:
    app: site
  ports:
    - name: http
      port: 8080
      targetPort: http
      protocol: TCP
EOF

# Have a look at what you wrote. The targetPort column reads "http", not 80.
kubectl -n web get svc site-svc
# NAME      TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)        AGE
# site-svc   ClusterIP   10.96.144.21   <none>        8080/TCP   10s

kubectl -n web get svc site-svc -o jsonpath='{.spec.ports[0]}'
# {"name":"http","port":8080,"protocol":"TCP","targetPort":"http"}

# The targetPort is a name, so the container has to declare a port with that
# name. It already does - check that it is still there and has not been
# renamed.
kubectl -n web get deploy site -o jsonpath='{.spec.template.spec.containers[0].ports}'
# [{"name":"http","containerPort":80,"protocol":"TCP"}]

# Now confirm the Service really selects the pods. A Service with the right
# fields and the wrong selector still has no endpoints.
kubectl -n web get endpoints site-svc
# NAME        ENDPOINTS                                                   AGE
# site-svc   10.244.0.9:80,10.244.0.10:80,10.244.0.11:80,...             12s

# The endpoint port is 80, even though the Service's port is 8080. That is the
# whole point: the Service answers on 8080 and forwards to the container's
# port 80 on the pod.

# If the endpoints are empty, work through it in this order:
#   1. does the Service's selector match the pods' labels?
#        kubectl -n web get deploy site -o jsonpath='{.spec.template.metadata.labels}'
#   2. does the container still declare a port named 'http'?
#        kubectl -n web get deploy site -o jsonpath='{.spec.template.spec.containers[0].ports}'
#   3. is the targetPort spelt exactly like the container's port name?
#        kubectl -n web get svc site-svc -o jsonpath='{.spec.ports[0].targetPort}'
