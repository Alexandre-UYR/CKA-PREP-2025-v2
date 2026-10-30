# Create the Pod with both containers.
#
# The fastest way to get a starting manifest is to let kubectl generate one and
# then edit it:
#
#   export do="--dry-run=client -o yaml"
#   kubectl run cache --image=redis:7 --dry-run=client -o yaml > pod.yaml
#
# but with two containers it is quicker to write the manifest out.

cat <<'EOF' > pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: cache
  namespace: multicontainer
  labels:
    app: cache
spec:
  containers:
    - name: redis
      image: redis:7
    - name: memcached
      image: memcached
EOF

kubectl apply -f pod.yaml

# Wait for both containers to be ready.
kubectl -n multicontainer wait --for=condition=Ready pod/cache --timeout=120s

# Check that redis really answers.
kubectl -n multicontainer exec cache -c redis -- redis-cli ping
# PONG

# A quicker way to see both containers at once:
kubectl -n multicontainer get pod cache
# NAME    READY   STATUS    RESTARTS   AGE
# cache   2/2     Running   0          30s
