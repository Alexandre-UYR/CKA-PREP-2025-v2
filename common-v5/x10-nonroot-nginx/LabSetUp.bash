#!/bin/bash
set -e

# x10 - nginx as somebody else
#
# The pre-state is a Pod that runs nginx as root, straight off the stock
# configuration, listening on port 80. The task is to make the same Pod run as
# UID 4242 and GID 4242 and still serve traffic.
#
# Two things get in the way, and both are in the image rather than in the
# Pod spec:
#
#   - a non-root user cannot bind a port below 1024, so the configuration has
#     to move to 8000;
#   - nginx writes its pid file and its temporary files under /var/run and
#     /var/cache, which are owned by root in the image.
#
# The ConfigMap `nginx-conf` is the configuration the candidate is meant to
# use: it already listens on 8000 and it names the paths nginx writes to.

NS=sec
POD=myuserpod
CM=nginx-conf
LABDIR=/tmp/cka-lab
CONF="$LABDIR/nginx.conf"

mkdir -p "$LABDIR"

# The configuration, staged on disk and then loaded into the ConfigMap.
cat > "$CONF" <<'EOF'
worker_processes 1;

error_log  /tmp/nginx-error.log warn;
pid        /var/run/nginx/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    access_log    /tmp/nginx-access.log;

    client_body_temp_path /tmp/client_temp;
    proxy_temp_path       /var/cache/nginx/proxy_temp;
    fastcgi_temp_path     /var/cache/nginx/fastcgi_temp;
    uwsgi_temp_path       /var/cache/nginx/uwsgi_temp;
    scgi_temp_path        /var/cache/nginx/scgi_temp;

    server {
        listen       8000;
        server_name  _;

        location / {
            default_type text/plain;
            return 200 "nginx is running as a non-root user\n";
        }
    }
}
EOF

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NS" create configmap "$CM" --from-file=nginx.conf="$CONF" \
  --dry-run=client -o yaml | kubectl apply -f -

# The Pod is part of the pre-state, so it is removed and re-created: the
# candidate is expected to change its securityContext, and a Pod's spec is
# immutable once it exists.
kubectl -n "$NS" delete pod "$POD" --ignore-not-found --timeout=60s >/dev/null 2>&1 || true

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $POD
  namespace: $NS
  labels:
    app: nginx
spec:
  containers:
    - name: nginx
      image: nginx:1.25
      ports:
        - containerPort: 80
EOF

echo "Waiting for the Pod to be running..."
i=0
READY=""
while [ "$i" -lt 90 ]; do
  READY=$(kubectl -n "$NS" get pod "$POD" \
            -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null) || READY=""
  [ "$READY" = "true" ] && break
  sleep 2
  i=$((i+2))
done

echo "x10 environment ready"
echo "   - namespace: $NS"
echo "   - ConfigMap: $CM (one key, nginx.conf - it listens on 8000 and it"
echo "     names the directories nginx writes its pid and temporary files to)"
echo "   - Pod: $POD (nginx:1.25, no securityContext, so it runs as root)"
echo "   - the stock configuration listens on port 80, which a non-root user"
echo "     cannot bind"
echo "   - Task: run the Pod as UID 4242 and GID 4242 and make it serve on 8000"

if [ "$READY" != "true" ]; then
  echo "   WARN: the Pod is not ready yet. Check:" >&2
  echo "         kubectl -n $NS describe pod $POD" >&2
fi
