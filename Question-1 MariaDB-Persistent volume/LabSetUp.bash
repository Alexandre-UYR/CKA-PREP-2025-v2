#!/bin/bash
set -e

echo "🔹 Creating namespace..."
kubectl create ns mariadb --dry-run=client -o yaml | kubectl apply -f -

# ---------------------------------------------------------------------------
# Clear whatever a previous attempt left behind, so the setup is safe to run
# twice: the PV below must never be left bound to an old claim.
# ---------------------------------------------------------------------------
echo "🔹 Clearing leftovers from a previous attempt..."
kubectl delete deployment mariadb -n mariadb --ignore-not-found --timeout=60s || true
kubectl delete pvc mariadb -n mariadb --ignore-not-found --timeout=60s || true
if kubectl get pv mariadb-pv >/dev/null 2>&1; then
  stale_ref="$(kubectl get pv mariadb-pv -o jsonpath='{.spec.claimRef.name}' 2>/dev/null || true)"
  if [ -n "$stale_ref" ]; then
    kubectl patch pv mariadb-pv --type=json -p '[{"op":"remove","path":"/spec/claimRef"}]'
  fi
fi

# Which StorageClass would a PVC get if it did not name one? The PV has to
# carry the same name, otherwise the PVC the candidate creates (which does not
# name a StorageClass) can never bind to it. With no default class, the API
# server gives such a PVC an empty storageClassName, so the PV must be empty too.
echo "🔹 Detecting the cluster's default StorageClass..."
SC="$(kubectl get storageclass -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -1)"
echo "   storage class for the PV: '${SC:-<none>}'"

echo "🔹 Creating PersistentVolume..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: mariadb-pv
  labels:
    app: mariadb
spec:
  capacity:
    storage: 250Mi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: "$SC"
  hostPath:
    path: /mnt/data/mariadb
EOF

echo "🔹 Creating initial PVC..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mariadb
  namespace: mariadb
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 250Mi
EOF

echo "🔹 Creating initial MariaDB Deployment..."
cat <<EOF > ~/mariadb-deploy.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mariadb
  namespace: mariadb
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mariadb
  template:
    metadata:
      labels:
        app: mariadb
    spec:
      containers:
      - name: mariadb
        image: mariadb:10.6
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: rootpass
        volumeMounts:
        - name: mariadb-storage
          mountPath: /var/lib/mysql
      volumes:
      - name: mariadb-storage
        persistentVolumeClaim:
          claimName: mariadb
EOF

kubectl apply -f ~/mariadb-deploy.yaml

echo "🔹 Waiting for MariaDB pod to start (this initialises the data directory)..."
if kubectl wait --for=condition=Available deployment/mariadb -n mariadb --timeout=120s; then
  echo "   MariaDB is up, /mnt/data/mariadb now holds a real data directory."
else
  echo "   ⚠️  MariaDB did not become Available in time." >&2
  echo "      The data-preservation check will fail until the pod has run at least once." >&2
fi

echo "🔹 Simulating accidental deletion of Deployment and PVC..."
kubectl delete deployment mariadb -n mariadb --ignore-not-found --timeout=120s || true
kubectl wait --for=delete pod -l app=mariadb -n mariadb --timeout=120s || true
kubectl delete pvc mariadb -n mariadb --ignore-not-found --timeout=120s || true

echo "🔹 Resetting PV for reuse (clearing any stale claimRef)..."
claim_ref=$(kubectl get pv mariadb-pv -o jsonpath='{.spec.claimRef.name}' 2>/dev/null || true)
if [ -n "$claim_ref" ]; then
  kubectl patch pv mariadb-pv --type=json -p '[{"op":"remove","path":"/spec/claimRef"}]'
fi

# Refresh the deployment manifest for practice: claimName intentionally left blank
cat <<'EOF' > ~/mariadb-deploy.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mariadb
  namespace: mariadb
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mariadb
  template:
    metadata:
      labels:
        app: mariadb
    spec:
      containers:
      - name: mariadb
        image: mariadb:10.6
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: rootpass
        volumeMounts:
        - name: mariadb-storage
          mountPath: /var/lib/mysql
      volumes:
      - name: mariadb-storage
        persistentVolumeClaim:
          claimName: ""
EOF

# The UID of the PV as it exists right now. The grader compares it with the UID
# at validation time: a PV that was deleted and re-created has a different UID,
# which is how "you reused the existing PV" is actually proved.
mkdir -p /tmp/cka-lab
kubectl get pv mariadb-pv -o jsonpath='{.metadata.uid}' > /tmp/cka-lab/q1.pv.uid

echo "✅ Lab setup complete!"
echo "   - PV retained and ready for reuse"
echo "   - Namespace: mariadb"
echo "   - Task: recreate PVC and deployment reusing existing PV (fill claimName in ~/mariadb-deploy.yaml)"
