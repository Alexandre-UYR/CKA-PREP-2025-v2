# 1. The Pod, with a generic ephemeral volume.
#
#    `ephemeral.volumeClaimTemplate` is a claim template with no owner of its
#    own: the Pod's controller creates the real claim from it when the Pod is
#    scheduled, and the Pod owns that claim.

cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: eph
  namespace: ephem
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      volumeMounts:
        - name: work
          mountPath: /work
  volumes:
    - name: work
      ephemeral:
        volumeClaimTemplate:
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 500Mi
EOF

kubectl -n ephem wait --for=condition=Ready pod/eph --timeout=120s

# 2. The claim exists while the Pod runs - and it is not yours: its name is
#    generated from the Pod name and the volume name.
kubectl -n ephem get pvc
# NAME          STATUS   VOLUME    CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# eph-work-r8vk4   Bound   pvc-2f0a9c9c6d   500Mi        RWO            standard       12s

# 3. And the Pod owns it.
kubectl -n ephem get pvc -o custom-columns=\
NAME:.metadata.name,\
KIND:.metadata.ownerReferences[0].kind,\
OWNER:.metadata.ownerReferences[0].name,\
REQUESTS:.spec.resources.requests.storage
# NAME             KIND   OWNER   REQUESTS
# eph-work-r8vk4   Pod    eph     500Mi

# The claim follows the Pod around and dies with it. Delete the Pod and the
# claim is garbage collected - that is the whole point of the owner reference.
kubectl -n ephem delete pod eph
kubectl -n ephem get pvc
# No resources found in ephem namespace.

# Create the Pod again if you want to carry on.
