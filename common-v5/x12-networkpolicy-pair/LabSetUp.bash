#!/bin/bash
set -e

# x12 - One door open, one door shut
#
# The pre-state is three Pods in one namespace and one Pod in another, with no
# NetworkPolicy anywhere. The candidate has to write two policies: one that
# opens a single door, and one that shuts another one completely.
#
# The namespaces are re-created on every run, so a policy left behind by a
# previous attempt does not survive and the starting state is always the same.

NS=netpol
FNS=frontend

for n in "$NS" "$FNS"; do
  kubectl delete namespace "$n" --ignore-not-found --timeout=180s >/dev/null 2>&1 || true
  kubectl create namespace "$n" --dry-run=client -o yaml | kubectl apply -f -
done

# The frontend namespace carries a label, so that a namespaceSelector can
# name it. Every namespace also carries kubernetes.io/metadata.name, which is
# the other way to select it.
kubectl label namespace "$FNS" name="$FNS" --overwrite >/dev/null

# The three Pods in the netpol namespace. my-httpd serves on port 80,
# my-proxy serves on port 80, and my-app is the Pod that has to be kept out.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: my-httpd
  namespace: $NS
  labels:
    app: httpd
spec:
  containers:
    - name: httpd
      image: httpd:2.4
      ports:
        - containerPort: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: my-proxy
  namespace: $NS
  labels:
    app: proxy
spec:
  containers:
    - name: proxy
      image: nginx:1.25-alpine
      ports:
        - containerPort: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: my-app
  namespace: $NS
  labels:
    app: myapp
spec:
  containers:
    - name: app
      image: nginx:1.25-alpine
      ports:
        - containerPort: 80
EOF

# A Service for each of the two Pods that get reached, so that the probes can
# use a name instead of an address.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: my-httpd
  namespace: $NS
spec:
  selector:
    app: httpd
  ports:
    - port: 80
      targetPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: my-proxy
  namespace: $NS
spec:
  selector:
    app: proxy
  ports:
    - port: 80
      targetPort: 80
EOF

# The client carries the label the policy has to select on, and it lives in
# another namespace on purpose.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: $FNS
  labels:
    httpd-access: "true"
spec:
  containers:
    - name: client
      image: curlimages/curl
      command: ["sleep", "3600"]
EOF

echo "Waiting for the four Pods to be ready..."
for pair in "$NS:3" "$FNS:1"; do
  n="${pair%%:*}"
  want="${pair##*:}"
  i=0
  while [ "$i" -lt 90 ]; do
    R=$(kubectl -n "$n" get pods -o jsonpath='{range .items[*]}{.status.containerStatuses[0].ready}{"\n"}{end}' 2>/dev/null | grep -c '^true$' || true)
    [ "${R:-0}" -ge "$want" ] && break
    sleep 2
    i=$((i+2))
  done
done

# Sanity check the pre-state: with no policy in place, the client reaches
# my-httpd. If it does not, the environment is broken in a way that is not
# the point of this question.
CODE=$(kubectl -n "$FNS" exec client -- curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
         "http://my-httpd.$NS.svc.cluster.local" 2>/dev/null || true)

echo "x12 environment ready"
echo "   - namespace $NS: Pods my-httpd (app=httpd), my-proxy (app=proxy),"
echo "     my-app (app=myapp), and Services my-httpd and my-proxy on port 80"
echo "   - namespace $FNS: Pod client, labelled httpd-access=true"
echo "   - no NetworkPolicy exists yet, so my-httpd and my-proxy are both"
echo "     reachable from everywhere"
echo "   - Task: write a policy that opens my-httpd to the labelled client"
echo "     only, and a policy that shuts my-proxy off completely"

if [ "$CODE" != "200" ]; then
  echo "   WARN: the client does not reach my-httpd before any policy exists (HTTP '${CODE:-no response}')." >&2
  echo "         Check: kubectl -n $FNS exec client -- curl -sv http://my-httpd.$NS.svc.cluster.local" >&2
fi
