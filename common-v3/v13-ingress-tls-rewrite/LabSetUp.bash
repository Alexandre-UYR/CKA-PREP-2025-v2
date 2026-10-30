#!/bin/bash
set -e

# v13 - Two hosts, two certificates
#
# The pre-state is the api, its Service, and - the interesting part - two TLS
# Secrets that already exist, each holding a self-signed certificate for a
# different host. The candidate has to wire both of them into one Ingress,
# one TLS entry per host.
#
# The namespace is recreated on every run, so the setup is idempotent and the
# starting state is always the same.

NS=ing
DEP=api

kubectl delete namespace "$NS" --ignore-not-found --timeout=180s >/dev/null 2>&1 || true
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

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
        - name: api
          image: nginx:1.25
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: $DEP
  namespace: $NS
spec:
  selector:
    app: $DEP
  ports:
    - name: http
      port: 80
      targetPort: 80
EOF

# Two self-signed certificates, one per host. The private keys never outlive
# the setup - they are written to a temporary directory that is removed again
# before this script exits.
if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required to generate the self-signed certificates for v13" >&2
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$TMP/api.key" -out "$TMP/api.crt" -subj "/CN=api.example.com" >/dev/null 2>&1
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$TMP/alt.key" -out "$TMP/alt.crt" -subj "/CN=alt.example.com" >/dev/null 2>&1

kubectl -n "$NS" create secret tls api-tls --cert="$TMP/api.crt" --key="$TMP/api.key" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" create secret tls alt-tls --cert="$TMP/alt.crt" --key="$TMP/alt.key" \
  --dry-run=client -o yaml | kubectl apply -f -

rm -rf "$TMP"

echo "Waiting for the api pod to be ready..."
i=0
while [ "$i" -lt 90 ]; do
  READY=$(kubectl -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
  [ "$READY" = "1" ] && break
  sleep 2
  i=$((i+2))
done
if [ "$READY" != "1" ]; then
  echo "   WARN: the api pod never became ready." >&2
fi

for s in api-tls alt-tls; do
  if ! kubectl -n "$NS" get secret "$s" >/dev/null 2>&1; then
    echo "   WARN: the TLS secret $s was not created." >&2
  fi
done

echo "v13 environment ready"
echo "   - namespace: $NS"
echo "   - Deployment $DEP (labels app=$DEP) and Service $DEP on port 80"
echo "   - TLS secret api-tls: self-signed certificate for CN=api.example.com"
echo "   - TLS secret alt-tls: self-signed certificate for CN=alt.example.com"
echo "   - no Ingress exists yet"
echo "   - Task: write one Ingress that terminates TLS for both hosts"
