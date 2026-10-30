# 1. Look at the Service as it is.
kubectl -n traps get svc svc -o yaml
# apiVersion: v1
# kind: Service
# metadata:
#   name: svc
#   namespace: traps
# spec:
#   clusterIP: 10.96.164.31
#   ports:
#   - port: 80
#     protocol: TCP
#     targetPort: 80
#   selector:
#     app: web
#   sessionAffinity: None
#   type: ClusterIP
#
# There is no kubectl.kubernetes.io/last-applied-configuration annotation.
# The Service was CREATED, not APPLIED, and kubectl create records nothing
# about how the object was made.

# 2. What happens if you apply straight away.
#
# kubectl apply is a three-way merge: the manifest you apply, the
# configuration it last applied, and the live object. With no annotation
# there is no "what it last applied", so kubectl has no baseline to diff
# against and tells you so. Worse, a Service's ports are merged by the port
# NUMBER, so the entry for port 80 survives and the entry for port 8080 is
# added next to it:
#
#   kubectl apply -f svc.yaml
#   Warning: resource service/svc is missing the
#   kubectl.kubernetes.io/last-applied-configuration annotation which is
#   required by kubectl apply to calculate the diff and preserve fields that
#   have not been changed
#   service/svc configured
#
#   kubectl -n traps get svc svc -o jsonpath='{.spec.ports}'
#   [{"port":80,"protocol":"TCP","targetPort":80},{"port":8080,"protocol":"TCP","targetPort":80}]
#
# The Service now exposes BOTH ports, and the annotation records only the
# one you applied.

# 3. Give kubectl a baseline: a manifest describing the Service as it is
#    now. Applying it changes nothing in the object, but it records the
#    current state as the last applied configuration.
#
#    Write it by hand, without the fields the API server fills in
#    (clusterIP, resourceVersion, uid) - a last applied configuration that
#    contains clusterIP makes the next apply try to delete an immutable
#    field, and the API server rejects that.
cat > /tmp/svc-baseline.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: svc
  namespace: traps
spec:
  type: ClusterIP
  selector:
    app: web
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
EOF

kubectl apply -f /tmp/svc-baseline.yaml
# service/svc configured
#
# The Service now has a last applied configuration, and it describes the
# Service exactly as it is, so nothing has changed yet.

# 4. Now the manifest you actually want, saved where the task says.
cat > /root/svc.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: svc
  namespace: traps
spec:
  type: ClusterIP
  selector:
    app: web
  ports:
    - port: 8080
      targetPort: 80
      protocol: TCP
EOF

kubectl apply -f /root/svc.yaml
# service/svc configured

# 5. Check it.
kubectl -n traps get svc svc -o jsonpath='{.spec.ports}'
# [{"port":8080,"protocol":"TCP","targetPort":80}]
#
# ONE port. The old entry for port 80 was in the last applied configuration
# and is not in the new manifest, so the apply removed it - that is what
# apply does with the fields it knows about.

kubectl -n traps get svc svc -o go-template='{{index .metadata.annotations "kubectl.kubernetes.io/last-applied-configuration"}}'
# {"apiVersion":"v1","kind":"Service","metadata":{"name":"svc","namespace":"traps"},"spec":{"type":"ClusterIP","selector":{"app":"web"},"ports":[{"port":8080,"targetPort":80,"protocol":"TCP"}]}}

# The annotation and the live object agree, which is the proof that the
# Service was APPLIED rather than only patched.

# 6. The Service still selects the pods, and it has endpoints.
kubectl -n traps get svc svc -o jsonpath='{.spec.selector}'
# {"app":"web"}

kubectl -n traps get endpoints svc
# NAME   ENDPOINTS           AGE
# svc    10.244.0.11:80      45s

# An alternative baseline, if you would rather not write one out: adopt the
# live object, then export it again - the adopt changes the object, so the
# copy you took before it now carries a stale resourceVersion and the next
# apply would be rejected as a conflict.
#
#   kubectl -n traps get svc svc -o yaml | kubectl apply -f -
#   kubectl -n traps get svc svc -o yaml > /root/svc.yaml
#   # edit the port 80 -> 8080, then:
#   kubectl apply -f /root/svc.yaml

# And for comparison, the tool that is NOT the answer here:
#
#   kubectl -n traps patch svc svc --type=merge \
#     -p '{"spec":{"ports":[{"port":8080,"targetPort":80}]}}'
#
# A patch changes one field and leaves everything else alone - and it writes
# no last applied configuration, so the Service is still an object that was
# never applied.
