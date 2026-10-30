#!/bin/bash
set -e

# x7 - A certificate, issued
#
# The pre-state is a cluster with cert-manager on it: the CRDs from the
# cert-manager v1.14.0 release, and a controller Deployment to drive them.
# The setup waits for the CRDs to be Established, because a Certificate
# created before that is rejected by the API server, and it waits for the
# controller to be available, because a Certificate created before that
# simply sits there doing nothing.
#
# The candidate is handed an Issuer manifest and asked to create a
# Certificate with it. The grader does not care whether the Certificate
# object exists - it cares whether the Secret with the issued certificate
# exists, because the Secret is what the controller produces.
#
# The CRDs are cluster-scoped. The reset must NOT delete them.

NS=pki
CM_NS=cert-manager
LABDIR=/tmp/cka-lab
ISSUER_FILE="$LABDIR/issuer.yaml"
CRD_FILE="$LABDIR/cert-manager.crds.yaml"
CRD_URL=${CERT_MANAGER_CRDS_URL:-https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.crds.yaml}
CTRL_IMAGE=${CERT_MANAGER_IMAGE:-quay.io/jetstack/cert-manager-controller:v1.14.0}
CRDS="certificates.cert-manager.io certificaterequests.cert-manager.io issuers.cert-manager.io clusterissuers.cert-manager.io orders.acme.cert-manager.io challenges.acme.cert-manager.io"

mkdir -p "$LABDIR"

# Start from a clean pre-state.
kubectl delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

# ---------------------------------------------------------------------------
# 1. The CRDs
#
# If the cluster already has cert-manager's CRDs, use them - re-installing a
# different version's CRDs over an existing installation is how people break
# a working cert-manager. Otherwise download the v1.14.0 CRD manifest and
# apply it. A copy can also be staged at $CRD_FILE beforehand, which is how
# this question is run on a machine with no network access.
# ---------------------------------------------------------------------------
if kubectl get crd certificates.cert-manager.io >/dev/null 2>&1; then
  echo "cert-manager's CRDs are already installed - using the ones that are there."
  CRDS_OK=1
else
  CRDS_OK=0
  if [ ! -s "$CRD_FILE" ]; then
    if command -v curl >/dev/null 2>&1; then
      echo "Downloading the cert-manager v1.14.0 CRDs..."
      if curl -fsSL --max-time 120 "$CRD_URL" -o "$CRD_FILE.tmp"; then
        mv "$CRD_FILE.tmp" "$CRD_FILE"
      else
        rm -f "$CRD_FILE.tmp"
        echo "⚠️  The CRD manifest could not be downloaded from $CRD_URL" >&2
        echo "    (no network access, or the release asset has moved)." >&2
        echo "    Stage a copy at $CRD_FILE and run the setup again if you need it." >&2
      fi
    else
      echo "⚠️  curl is not on the PATH, so the CRD manifest cannot be downloaded." >&2
      echo "    Stage a copy at $CRD_FILE and run the setup again if you need it." >&2
    fi
  else
    echo "Using the CRD manifest already staged at $CRD_FILE."
  fi

  if [ -s "$CRD_FILE" ]; then
    echo "Applying the cert-manager CRDs..."
    kubectl apply -f "$CRD_FILE" >/dev/null
    CRDS_OK=1
  fi
fi

# Wait for the CRDs to be Established. A CRD that exists is not yet usable:
# until the API server has established the schema, the API rejects any
# Certificate object with "no matches for kind".
if [ "$CRDS_OK" = "1" ]; then
  echo "Waiting for the cert-manager CRDs to be Established..."
  for c in $CRDS; do
    i=0
    EST=""
    while [ "$i" -lt 30 ]; do
      EST=$(kubectl get crd "$c" -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' 2>/dev/null || true)
      [ "$EST" = "True" ] && break
      i=$((i+1)); sleep 2
    done
    if [ "$EST" = "True" ]; then
      echo "   - $c: Established"
    else
      echo "   - $c: NOT established yet" >&2
    fi
  done
else
  echo "⚠️  cert-manager's CRDs are NOT installed." >&2
  echo "    This question cannot be answered without them: there is no" >&2
  echo "    Certificate kind to create. Everything else below still runs, so" >&2
  echo "    that the candidate at least has the Issuer manifest to work with." >&2
fi

# ---------------------------------------------------------------------------
# 2. The controller
#
# A minimal cert-manager controller: the ServiceAccount it runs as, the
# permissions it needs over the resources it reconciles, and the Deployment
# itself. The webhook and the CA injector are deliberately left out - they
# are not needed to issue a certificate from a self-signed Issuer, and the
# validating webhook would get in the way of creating the Certificate at
# all if it were installed without its certificates.
# ---------------------------------------------------------------------------
echo "Installing the cert-manager controller..."

kubectl create namespace "$CM_NS" --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cert-manager
  namespace: $CM_NS
  labels:
    app: cert-manager
EOF

cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cert-manager-controller-cka
  labels:
    app: cert-manager
rules:
  - apiGroups: [""]
    resources: ["secrets", "services", "configmaps"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: [""]
    resources: ["pods", "nodes", "namespaces"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["coordination.k8s.io"]
    resources: ["leases"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["cert-manager.io"]
    resources: ["certificates", "certificaterequests", "issuers", "clusterissuers", "orders", "challenges"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["cert-manager.io"]
    resources: ["certificates/status", "certificaterequests/status", "issuers/status", "clusterissuers/status", "orders/status", "challenges/status"]
    verbs: ["get", "update", "patch"]
  - apiGroups: ["cert-manager.io"]
    resources: ["certificates/finalizers", "certificaterequests/finalizers", "issuers/finalizers", "clusterissuers/finalizers", "orders/finalizers", "challenges/finalizers"]
    verbs: ["update"]
  - apiGroups: ["apiextensions.k8s.io"]
    resources: ["customresourcedefinitions"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["admissionregistration.k8s.io"]
    resources: ["validatingwebhookconfigurations", "mutatingwebhookconfigurations"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apiregistration.k8s.io"]
    resources: ["apiservices"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["authorization.k8s.io"]
    resources: ["subjectaccessreviews"]
    verbs: ["create"]
EOF

cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cert-manager-controller-cka
  labels:
    app: cert-manager
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cert-manager-controller-cka
subjects:
  - kind: ServiceAccount
    name: cert-manager
    namespace: $CM_NS
EOF

cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cert-manager
  namespace: $CM_NS
  labels:
    app: cert-manager
    app.kubernetes.io/name: cert-manager
    app.kubernetes.io/instance: cert-manager
    app.kubernetes.io/component: controller
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cert-manager
      app.kubernetes.io/name: cert-manager
      app.kubernetes.io/instance: cert-manager
      app.kubernetes.io/component: controller
  template:
    metadata:
      labels:
        app: cert-manager
        app.kubernetes.io/name: cert-manager
        app.kubernetes.io/instance: cert-manager
        app.kubernetes.io/component: controller
    spec:
      serviceAccountName: cert-manager
      containers:
        - name: cert-manager-controller
          image: $CTRL_IMAGE
          args:
            - --v=2
            - --cluster-resource-namespace=\$(POD_NAMESPACE)
          env:
            - name: POD_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
          resources:
            requests:
              cpu: 10m
              memory: 32Mi
            limits:
              cpu: 200m
              memory: 256Mi
EOF

echo "Waiting for the cert-manager controller to be available..."
if ! kubectl -n "$CM_NS" rollout status deployment/cert-manager --timeout=180s; then
  echo "⚠️  The cert-manager controller did not become available." >&2
  echo "    Check: kubectl -n $CM_NS get pods" >&2
  echo "    and:   kubectl -n $CM_NS logs deploy/cert-manager" >&2
  echo "    The image $CTRL_IMAGE may not be pullable without network access." >&2
fi

# ---------------------------------------------------------------------------
# 3. The Issuer manifest the candidate is given.
# ---------------------------------------------------------------------------
cat > "$ISSUER_FILE" <<EOF
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: selfsigned
  namespace: $NS
spec:
  selfSigned: {}
EOF

CTRLREADY=$(kubectl -n "$CM_NS" get deploy cert-manager -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
CRDEST=$(kubectl get crd certificates.cert-manager.io -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' 2>/dev/null || true)

echo "✅ x7 environment ready"
echo "   - namespace: $NS"
echo "   - cert-manager CRDs: ${CRDEST:-not established}"
echo "   - cert-manager controller: ${CTRLREADY:-0} ready replica(s) in namespace $CM_NS"
echo "   - Issuer manifest waiting at: $ISSUER_FILE"
echo "   - Task: apply the Issuer, create the Certificate 'test-cert' with"
echo "     commonName example.com, dnsNames [example.com] and secretName test,"
echo "     and prove it by showing the Secret 'test' with the issued certificate"
