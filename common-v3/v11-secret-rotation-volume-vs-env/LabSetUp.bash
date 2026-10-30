#!/bin/bash
set -e

# v11 - Which one sees the new value?
#
# The pre-state is a Deployment that reads one Secret twice: once as an
# environment variable and once as a mounted volume. The setup rotates the
# Secret AFTER the pod has already started, so the container is holding the
# old value in its environment while the mounted file is a projection the
# kubelet refreshes on its own schedule.
#
# The namespace is recreated on every run, so the setup is idempotent and the
# starting state is always the same.

NS=rot
DEP=app
SEC=app-secret

kubectl delete namespace "$NS" --ignore-not-found --timeout=180s >/dev/null 2>&1 || true
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

# The Secret starts out holding the OLD value.
kubectl -n "$NS" create secret generic "$SEC" --from-literal=TOKEN=old-value \
  --dry-run=client -o yaml | kubectl apply -f -

# The Deployment reads the Secret twice: as the environment variable TOKEN,
# and as a volume mounted at /etc/secret.
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEP
  namespace: $NS
  labels:
    app: $DEP
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $DEP
  template:
    metadata:
      labels:
        app: $DEP
    spec:
      containers:
        - name: app
          image: nginx:1.25
          env:
            - name: TOKEN
              valueFrom:
                secretKeyRef:
                  name: $SEC
                  key: TOKEN
          volumeMounts:
            - name: secret-vol
              mountPath: /etc/secret
              readOnly: true
      volumes:
        - name: secret-vol
          secret:
            secretName: $SEC
EOF

echo "Waiting for the pod to start, so its environment captures the OLD value..."
READY=""
i=0
while [ "$i" -lt 90 ]; do
  READY=$(kubectl -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
  [ "$READY" = "1" ] && break
  sleep 2
  i=$((i+2))
done

POD=$(kubectl -n "$NS" get pods -l "app=$DEP" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
ENVVAL=""
if [ -n "$POD" ]; then
  ENVVAL=$(kubectl -n "$NS" exec "$POD" -- printenv TOKEN 2>/dev/null | tr -d '\r\n' || true)
fi

if [ "$READY" != "1" ]; then
  echo "   WARN: the pod never became ready, so the environment may not hold the old value." >&2
fi
if [ "$ENVVAL" != "old-value" ]; then
  echo "   WARN: the container's TOKEN environment variable is '${ENVVAL:-<unknown>}', not 'old-value'." >&2
  echo "         The pre-state should show the stale value. Check:" >&2
  echo "         kubectl -n $NS describe pod -l app=$DEP" >&2
fi

# Now rotate the Secret. The container is already running, so nothing in the
# pod changes on its own - except the mounted file, which the kubelet rewrites
# in place once it gets around to it.
NEWB64=$(printf '%s' 'new-value' | base64 | tr -d '\n')
kubectl -n "$NS" patch secret "$SEC" --type=merge -p "{\"data\":{\"TOKEN\":\"$NEWB64\"}}"

AFTER=""
if [ -n "$POD" ]; then
  AFTER=$(kubectl -n "$NS" exec "$POD" -- printenv TOKEN 2>/dev/null | tr -d '\r\n' || true)
fi
if [ "$AFTER" != "old-value" ]; then
  echo "   WARN: after the rotation the container's TOKEN is '${AFTER:-<unknown>}', not 'old-value'." >&2
  echo "         The pod should still be running with the value it started with." >&2
fi

echo "v11 environment ready"
echo "   - namespace: $NS"
echo "   - Secret $SEC: TOKEN rotated from old-value to new-value"
echo "   - Deployment $DEP reads it twice: as env TOKEN, and as a volume at /etc/secret"
echo "   - the container's environment still holds: ${AFTER:-<unknown>}"
echo "   - the mounted file is a projection; the kubelet refreshes it on its own schedule (up to about two minutes)"
echo "   - Task: work out which of the two updates by itself, and make the container serve the new value"
