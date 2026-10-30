#!/bin/bash
set -e

# w17 - Move the routing to the new API without changing the outside
#
# The pre-state is an Ingress that serves one hostname over TLS, and the
# Gateway API is not there yet. The candidate has to put the Gateway API in
# and rebuild the same routing with it, then take the Ingress away.
#
# One subtlety in the pre-state, and it is the point of the question:
#
#   the `gatewayclasses` CRD IS installed, and the GatewayClass `nginx-class`
#   exists, but the `gateways` and `httproutes` CRDs are NOT.
#
# That is a real state a cluster can be in: the CRDs were installed, the
# GatewayClass was created, and the two CRDs the Gateway and the HTTPRoute
# need have since been removed. Deleting a CRD deletes every object of that
# kind, so the GatewayClass only survives because its own CRD is still
# there. The candidate can read the GatewayClass but cannot create a Gateway
# or an HTTPRoute until the CRDs are put back.
#
# Everything the setup writes to disk goes under /tmp/cka-lab/gateway, and the
# reset uses the copies kept there to put the pre-state back.

NS=gw
DEP=web
SVC=web
ING=web
SEC=web-tls
GWCLASS=nginx-class
GATEWAY=web-gateway
ROUTE=web-route
HOST=gateway.web.k8s.local

DIR=/tmp/cka-lab/gateway
GWAPI_VERSION=v1.2.0
GWAPI_URL="https://github.com/kubernetes-sigs/gateway-api/releases/download/${GWAPI_VERSION}/standard-install.yaml"
GWAPI_FILE="$DIR/standard-install.yaml"

rm -rf "$DIR"
mkdir -p "$DIR"

# ---------------------------------------------------------------------------
# The Gateway API CRDs
# ---------------------------------------------------------------------------

CRDS_READY="no"
if command -v curl >/dev/null 2>&1; then
  if curl -fsSL -m 45 -o "$GWAPI_FILE" "$GWAPI_URL" 2>/dev/null; then
    if kubectl apply -f "$GWAPI_FILE" >/dev/null 2>&1; then
      CRDS_READY="yes"
    fi
  fi
fi

if [ "$CRDS_READY" = "yes" ]; then
  echo "   the Gateway API CRDs are installed"
else
  echo "   WARN: the Gateway API CRDs could not be downloaded from $GWAPI_URL" >&2
  echo "         The GatewayClass '$GWCLASS' cannot be created without them, and" >&2
  echo "         the candidate will have to install the CRDs and create it." >&2
fi

# The pre-state keeps the GatewayClass and loses the two CRDs the candidate
# has to put back.
if [ "$CRDS_READY" = "yes" ]; then
  kubectl delete crd gateways.gateway.networking.k8s.io --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete crd httproutes.gateway.networking.k8s.io --ignore-not-found >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------------
# The manifests of the pre-state
# ---------------------------------------------------------------------------

cat > "$DIR/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: gw
  labels:
    app: web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: nginx
          image: nginx:1.25
          ports:
            - containerPort: 80
EOF

cat > "$DIR/service.yaml" <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: gw
  labels:
    app: web
spec:
  selector:
    app: web
  ports:
    - name: http
      port: 80
      targetPort: 80
      protocol: TCP
EOF

cat > "$DIR/gatewayclass.yaml" <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: nginx-class
spec:
  controllerName: example.net/nginx-gateway-controller
EOF

cat > "$DIR/ingress.yaml" <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web
  namespace: gw
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  tls:
    - hosts:
        - gateway.web.k8s.local
      secretName: web-tls
  rules:
    - host: gateway.web.k8s.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web
                port:
                  number: 80
EOF

# ---------------------------------------------------------------------------
# The TLS secret: a self-signed certificate for the hostname
# ---------------------------------------------------------------------------

CRT_B64=""
KEY_B64=""
if command -v openssl >/dev/null 2>&1; then
  if ! openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
        -keyout "$DIR/tls.key" -out "$DIR/tls.crt" \
        -subj "/CN=gateway.web.k8s.local" \
        -addext "subjectAltName=DNS:gateway.web.k8s.local" >/dev/null 2>&1; then
    # An older openssl has no -addext: the certificate is still fine without
    # the subject alternative name.
    openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
      -keyout "$DIR/tls.key" -out "$DIR/tls.crt" \
      -subj "/CN=gateway.web.k8s.local" >/dev/null 2>&1 || true
  fi
  if [ -s "$DIR/tls.crt" ] && [ -s "$DIR/tls.key" ]; then
    CRT_B64=$(base64 < "$DIR/tls.crt" | tr -d '\n')
    KEY_B64=$(base64 < "$DIR/tls.key" | tr -d '\n')
  fi
fi

if [ -z "$CRT_B64" ]; then
  echo "   WARN: openssl is not available, so the certificate could not be generated." >&2
  echo "         A placeholder is used instead - the Secret and its name still matter," >&2
  echo "         but the certificate in it is not a real one." >&2
  CRT_B64="cGxhY2Vob2xkZXItY2VydGlmaWNhdGUtbm90LWEtcmVhbC1jZXJ0aWZpY2F0ZQ=="
  KEY_B64="cGxhY2Vob2xkZXItbm90LWEtcmVhbC1rZXk="
fi

cat > "$DIR/secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: $SEC
  namespace: $NS
type: kubernetes.io/tls
data:
  tls.crt: $CRT_B64
  tls.key: $KEY_B64
EOF

# ---------------------------------------------------------------------------
# Put the pre-state in place
# ---------------------------------------------------------------------------

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

# Anything the candidate built in an earlier attempt goes first.
kubectl delete gateway "$GATEWAY" -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
kubectl delete httproute "$ROUTE" -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
kubectl delete ingress "$ING" -n "$NS" --ignore-not-found >/dev/null 2>&1 || true

kubectl apply -f "$DIR/deployment.yaml" >/dev/null
kubectl apply -f "$DIR/service.yaml" >/dev/null
kubectl apply -f "$DIR/secret.yaml" >/dev/null
kubectl apply -f "$DIR/ingress.yaml" >/dev/null

if kubectl get crd gatewayclasses.gateway.networking.k8s.io >/dev/null 2>&1; then
  kubectl apply -f "$DIR/gatewayclass.yaml" >/dev/null
fi

echo "Waiting for the deployment to be available..."
kubectl -n "$NS" rollout status deployment/"$DEP" --timeout=180s >/dev/null 2>&1 || true

# Record what the pre-state looks like, so the grader can tell that the
# Service and the Deployment were left alone, and what the Ingress was.
: > "$DIR/pre-state-uid.txt"
for obj in "deployment/$DEP" "service/$SVC" "ingress/$ING"; do
  OBJUID=$(kubectl -n "$NS" get "${obj%%/*}" "${obj##*/}" -o jsonpath='{.metadata.uid}' 2>/dev/null || true)
  if [ -n "$OBJUID" ]; then
    printf '%s %s\n' "$obj" "$OBJUID" >> "$DIR/pre-state-uid.txt"
  fi
done

INGUID=$(grep "^ingress/$ING " "$DIR/pre-state-uid.txt" 2>/dev/null | awk '{print $2}')

echo "✅ w17 environment ready"
echo "   - namespace: $NS"
echo "   - Deployment $DEP (nginx:1.25, 1 replica) and Service $SVC on port 80"
echo "   - Secret $SEC: a self-signed certificate for $HOST"
echo "   - Ingress $ING: host $HOST, TLS from secret $SEC, path / -> Service $SVC:80"
echo "     (UID ${INGUID:-unknown})"
echo "   - GatewayClass $GWCLASS, controller example.net/nginx-gateway-controller"
echo "   - the `gateways` and `httproutes` CRDs are NOT installed, so the"
echo "     Gateway and the HTTPRoute cannot be created until they are put back"
echo "   - Task: install the CRDs, move the routing to a Gateway and an HTTPRoute,"
echo "     and remove the Ingress"
