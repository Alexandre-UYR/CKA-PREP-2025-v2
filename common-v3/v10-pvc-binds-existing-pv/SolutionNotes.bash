# 1. Look at the claim.
kubectl -n bind get pvc data
# NAME   STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
# data   Pending                                      default        <none>                  30s

kubectl -n bind describe pvc data
# Events:
#   Warning  ProvisioningFailed  external-provisioner  ... no persistent volumes available
#   for this claim and this claim has a storage class that does not match
#
# The StorageClass column is not empty - the API server filled it in. The
# candidate never asked for it.

kubectl -n bind get pvc data -o jsonpath='{.spec.storageClassName}{"\n"}'
# default

# 2. Look at the volume.
kubectl get pv data-pv
# NAME       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS   REASON   AGE
# data-pv    500Mi      RWO            Retain           Available            fast              30s

kubectl get pv data-pv -o jsonpath='{.spec.storageClassName}{"\n"}'
# fast

# The size agrees (500Mi on both sides), the access modes agree (RWO on both
# sides), and the volume is Available - nobody has claimed it. The classes do
# not agree: the claim says `default`, the volume says `fast`. That is the
# whole fault.

# 3. The cheapest fix. The claim is not bound, so its storageClassName is
#    still mutable.
kubectl -n bind patch pvc data --type=merge \
  -p '{"spec":{"storageClassName":"fast"}}'

# Deleting and re-creating the claim with the right class works just as well,
# and the task allows it:
#
#   kubectl -n bind delete pvc data
#   kubectl -n bind apply -f - <<'EOF'
#   apiVersion: v1
#   kind: PersistentVolumeClaim
#   metadata:
#     name: data
#     namespace: bind
#   spec:
#     accessModes:
#       - ReadWriteOnce
#     storageClassName: fast
#     resources:
#       requests:
#         storage: 500Mi
#   EOF

# 4. Watch it bind.
kubectl -n bind get pvc data
# NAME   STATUS    VOLUME    CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
# data   Bound     data-pv   500Mi      RWO            fast           <none>                  30s

kubectl get pv data-pv
# NAME       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM       STORAGECLASS   REASON   AGE
# data-pv    500Mi      RWO            Retain           Bound       bind/data   fast                  30s

# The volume is the same volume - same UID, same data, still Retain. The
# binder set the claimRef on it:
#
#   kubectl get pv data-pv -o jsonpath='{.spec.claimRef}{"\n"}'
#   {"apiVersion":"v1","kind":"PersistentVolumeClaim","name":"data","namespace":"bind","uid":"..."}

# A note on what NOT to do: deleting the PersistentVolume and re-creating it
# would bind the claim, but it throws away the volume's identity and the data
# that is on it. The UID would change, and the task says the volume has to
# survive.
