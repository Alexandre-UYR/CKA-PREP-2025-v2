# 1. Look at the Pod's events - that is where the reason is.
kubectl -n diag get pods
# NAME   READY   STATUS              RESTARTS   AGE
# web    0/1     ContainerCreating   0          20s

kubectl -n diag describe pod web
# Events:
#   Type     Reason     From               Message
#   ----     ------     ----               -------
#   Warning  Failed     kubelet            Error: configmap "app-config" not found

# The same thing, shorter:
kubectl -n diag get events --sort-by=.lastTimestamp
# LAST SEEN   TYPE      REASON   OBJECT   MESSAGE
# 5s          Warning   Failed   pod/web   Error: configmap "app-config" not found

# The Pod's spec tells you what it is asking for.
kubectl -n diag get pod web -o jsonpath='{.spec.containers[0].envFrom}'
# [{"configMapRef":{"name":"app-config"}}]

# 2. The fix is to CREATE the missing ConfigMap. The Pod's envFrom is
#    immutable, so you cannot repoint it - and the task says not to re-create
#    the Pod either.
kubectl -n diag create configmap app-config --from-literal=MODE=prod

# 3. The kubelet retries on its own; there is nothing to restart.
kubectl -n diag get pods -w
# NAME   READY   STATUS    RESTARTS   AGE
# web    1/1     Running   0          35s

# 4. Verify the variable really is set inside the Pod.
kubectl -n diag exec web -- printenv MODE
# prod

# And confirm you did not re-create it:
kubectl -n diag get pod web -o jsonpath='{.metadata.uid}'
# 6b1c0f3e-2f5a-4a1b-9c7d-1e2f3a4b5c6d
#
# The UID recorded at setup was the same one.
