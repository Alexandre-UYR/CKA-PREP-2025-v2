#!/bin/bash
set -e

# c10 is about two things: a StorageClass that allows volume expansion, and a
# claim that has to name that class explicitly. The cluster's default class is
# left exactly as it is - whether it allows expansion is part of the question.

NS=resize
SC=expandable

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

# Anything a previous attempt created goes first, so the pre-state is the
# namespace and the class and nothing else.
kubectl -n "$NS" delete pvc expand-pvc --ignore-not-found --timeout=60s >/dev/null 2>&1 || true
kubectl delete pv expand-pv --ignore-not-found >/dev/null 2>&1 || true

# Recreate the class from scratch, so a class that was edited during a
# previous attempt cannot change the answer.
kubectl delete sc "$SC" --ignore-not-found >/dev/null

cat <<'EOF' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: expandable
provisioner: rancher.io/local-path
allowVolumeExpansion: true
reclaimPolicy: Delete
EOF

echo "✅ c10 environment ready"
echo "   - namespace: $NS"
echo "   - any volume or claim left over from a previous attempt was removed"
echo "   - StorageClass $SC: provisioner rancher.io/local-path, allowVolumeExpansion: true"
echo "   - StorageClasses in this cluster:"
kubectl get sc
echo "   - Task: create the PV expand-pv and the claim expand-pvc, then expand the claim to 70Mi"
