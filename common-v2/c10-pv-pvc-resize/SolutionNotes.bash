# The reference answer for c10.
#
# The StorageClass expandable already exists and already allows expansion.
# The claim has to name it: a claim that leaves storageClassName out is
# defaulted to the cluster's default class, and that class does not allow
# expansion, so the resize would be refused by the API server.

# ---- 1. the volume ----

cat <<'EOF' > pv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: expand-pv
spec:
  capacity:
    storage: 100Mi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: expandable
  hostPath:
    path: /tmp/expand-data
EOF

kubectl apply -f pv.yaml

# ---- 2. the claim ----
#
# volumeName points the claim at the static volume. Without it the class's
# provisioner would create a different volume and expand-pv would stay
# Available.

cat <<'EOF' > pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: expand-pvc
  namespace: resize
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: expandable
  volumeName: expand-pv
  resources:
    requests:
      storage: 10Mi
EOF

kubectl apply -f pvc.yaml

# ---- 3. wait for the claim to bind ----
#
# Only a bound claim can be expanded, so this has to happen first.

kubectl -n resize wait --for=jsonpath='{.status.phase}'=Bound pvc/expand-pvc --timeout=60s

# ---- 4. expand it ----

kubectl -n resize patch pvc expand-pvc --type=merge \
  -p '{"spec":{"resources":{"requests":{"storage":"70Mi"}}}}'

kubectl -n resize get pvc expand-pvc
# NAME        STATUS   VOLUME      CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# expand-pvc  Bound    expand-pv   100Mi      RWO            expandable      25s

# The request is what the expansion changed:
kubectl -n resize get pvc expand-pvc -o jsonpath='{.spec.resources.requests.storage}{"\n"}'
# 70Mi

# The volume is untouched: hostPath has no resizing support, so there was
# nothing for the backend to grow.
kubectl get pv expand-pv -o jsonpath='{.spec.capacity.storage}{"\n"}'
# 100Mi

# If the resize is refused, the API server says why:
#
#   The PersistentVolumeClaim "expand-pvc" is forbidden: only dynamically
#   provisioned pvc can be resized and the storageclass that provisions the
#   pvc must support resize
#
# That message means the claim is on a class that does not allow expansion.
# Check which class the claim names:
#
#   kubectl -n resize get pvc expand-pvc -o jsonpath='{.spec.storageClassName}{"\n"}'
#
# and whether that class allows expansion:
#
#   kubectl get sc expandable -o jsonpath='{.allowVolumeExpansion}{"\n"}'
