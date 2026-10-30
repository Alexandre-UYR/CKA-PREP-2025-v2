#!/bin/bash
set -e

# w16 - Get a Host header to the right place
#
# The pre-state is a namespace `web` with a third page behind a Service, and
# no ingress controller at all. The candidate installs Traefik, writes an
# Ingress, and then proves the routing works by sending a request with the
# right Host header from inside the cluster.
#
# The nginx configuration behind the third page echoes a marker string and the
# hostname it was reached under, so the response says both that the request
# reached the right place and that the Host header decided where it went.

NS=web
TRAEFIK_NS=traefik
DEP=thirdpage
SVC=thirdpage
CM=nginx-conf
ING=web
RELEASE=traefik
MARKER=thirdpage-marker

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

# Traefik must NOT be there: the candidate installs it.
if command -v helm >/dev/null 2>&1; then
  helm uninstall "$RELEASE" -n "$TRAEFIK_NS" >/dev/null 2>&1 || true
fi
kubectl delete namespace "$TRAEFIK_NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# Clear anything an earlier attempt left behind.
kubectl delete ingress "$ING" -n "$NS" --ignore-not-found >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# The nginx configuration behind the third page
# ---------------------------------------------------------------------------

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: $CM
  namespace: $NS
data:
  default.conf: |
    server {
        listen 80;
        server_name www.example.com;

        location / {
            default_type text/plain;
            return 200 "$MARKER host=\$host";
        }
    }
EOF

# ---------------------------------------------------------------------------
# The third page
# ---------------------------------------------------------------------------

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
        - name: nginx
          image: nginx:1.25
          ports:
            - containerPort: 80
          volumeMounts:
            - name: nginx-conf
              mountPath: /etc/nginx/conf.d/default.conf
              subPath: default.conf
      volumes:
        - name: nginx-conf
          configMap:
            name: $CM
EOF

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: $SVC
  namespace: $NS
spec:
  selector:
    app: $DEP
  ports:
    - name: http
      port: 80
      targetPort: 80
      protocol: TCP
EOF

# The pods read the configuration when nginx starts, so a pod that was started
# against an older configuration is replaced.
kubectl -n "$NS" delete pods -l "app=$DEP" --ignore-not-found >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# A pod with curl in it, to send the request from inside the cluster
# ---------------------------------------------------------------------------

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: probe
  namespace: $NS
  labels:
    cka.probe: "true"
spec:
  containers:
    - name: probe
      image: curlimages/curl
      command: ["sleep", "3600"]
EOF

echo "Waiting for the third page and the probe pod to be ready..."
for i in $(seq 1 60); do
  R=$(kubectl -n "$NS" get pods -o jsonpath='{range .items[*]}{.status.containerStatuses[0].ready}{"\n"}{end}' 2>/dev/null | grep -c '^true$' || true)
  [ "${R:-0}" -ge 2 ] && break
  sleep 2
done

READY=$(kubectl -n "$NS" get pods -l "app=$DEP" -o jsonpath='{range .items[0].status.containerStatuses[*]}{.ready}{"\n"}{end}' 2>/dev/null | grep -c '^true$' || true)
PROBEREADY=$(kubectl -n "$NS" get pod probe -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || true)

if [ "${READY:-0}" -lt 1 ]; then
  echo "   WARN: the third page is not ready. Check: kubectl -n $NS describe pod -l app=$DEP" >&2
fi
if [ "$PROBEREADY" != "true" ]; then
  echo "   WARN: the probe pod is not ready. The live check needs it (and registry access" >&2
  echo "         for curlimages/curl). Check: kubectl -n $NS describe pod probe" >&2
fi

echo "✅ w16 environment ready"
echo "   - namespace: $NS"
echo "   - Deployment $DEP (nginx:1.25, 1 replica) behind Service $SVC on port 80"
echo "   - ConfigMap $CM: the page answers '$MARKER host=<the hostname it was asked for>'"
echo "   - pod 'probe' in namespace $NS, with curl in it"
echo "   - no ingress controller: Traefik is not installed"
echo "   - Task: install the Traefik chart into namespace $TRAEFIK_NS, write the Ingress"
echo "     $ING for host www.example.com, and prove the routing with a Host header"
