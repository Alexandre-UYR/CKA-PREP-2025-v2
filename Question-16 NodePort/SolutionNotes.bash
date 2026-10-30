# Add container port to deployment.
# The container inside a deployment created with `kubectl create deployment
# nodeport-deployment` is named after the deployment, not "nginx".
kubectl patch deployment nodeport-deployment -n relative -p '{
  "spec":{"template":{"spec":{"containers":[{
    "name":"nodeport-deployment",
    "ports":[{"name":"http","containerPort":80,"protocol":"TCP"}]
  }]}}}}'
kubectl get deploy nodeport-deployment -n relative -o wide

# Create NodePort service on 30080
cat <<'EOF' > svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: nodeport-service
  namespace: relative
spec:
  type: NodePort
  selector:
    app: nodeport-deployment
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
    nodePort: 30080
EOF
kubectl apply -f svc.yaml
kubectl get svc nodeport-service -n relative -o wide

# Also expose the individual pods. The wording of this step is ambiguous in the
# task, and both of these are accepted:
#
#   publishNotReadyAddresses: true   publishes each individual pod address,
#                                    including pods that are not ready
#   externalTrafficPolicy: Local     preserves the client source IP and routes
#                                    only to node-local endpoints
kubectl patch svc nodeport-service -n relative -p \
  '{"spec":{"publishNotReadyAddresses":true}}'

# Test: curl http://<nodeIP>:30080
