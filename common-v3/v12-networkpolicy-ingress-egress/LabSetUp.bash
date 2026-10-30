#!/bin/bash
set -e

# v12 - Open the door, but only that door
#
# The pre-state is an api that everybody can reach, in a namespace with no
# policy at all. The candidate has to write a policy that opens ingress from
# one namespace and closes everything else - including, if they forget it, the
# api's own egress, which silently breaks DNS.
#
# The namespaces are recreated on every run, so the setup is idempotent and the
# starting state is always the same.

NS=pol
CLI=client
OTH=other
DEP=api

for n in "$NS" "$CLI" "$OTH"; do
  kubectl delete namespace "$n" --ignore-not-found --timeout=180s >/dev/null 2>&1 || true
  kubectl create namespace "$n" --dry-run=client -o yaml | kubectl apply -f -
done

# The client namespace carries a label, so that a namespaceSelector can name
# it. The other namespace deliberately carries none.
kubectl label namespace "$CLI" name="$CLI" --overwrite >/dev/null

# The api workload and its Service.
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
          image: nginx:1.25-alpine
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

# One probe pod in each of the two client namespaces. They are plain sleepers:
# the candidate (and the validator) run curl from inside them.
for n in "$CLI" "$OTH"; do
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: probe
  namespace: $n
  labels:
    app: probe
spec:
  containers:
    - name: probe
      image: curlimages/curl
      command: ["sleep", "3600"]
EOF
done

echo "Waiting for the api pod and the two probe pods to be ready..."
for n in "$NS" "$CLI" "$OTH"; do
  i=0
  while [ "$i" -lt 90 ]; do
    R=$(kubectl -n "$n" get pods -o jsonpath='{range .items[*]}{.status.containerStatuses[0].ready}{"\n"}{end}' 2>/dev/null | grep -c '^true$' || true)
    [ "$R" -ge 1 ] && break
    sleep 2
    i=$((i+2))
  done
done

# Sanity check the pre-state: with no policy in place, the api is reachable
# from anywhere. If it is not, the environment is broken in a way that is not
# the point of this question.
CLIPOD=$(kubectl -n "$CLI" get pods -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
CODE=""
if [ -n "$CLIPOD" ]; then
  CODE=$(kubectl -n "$CLI" exec "$CLIPOD" -- curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
           "http://$DEP.$NS.svc.cluster.local" 2>/dev/null || true)
fi
if [ "$CODE" != "200" ]; then
  echo "   WARN: the api is not reachable from namespace $CLI before any policy exists (HTTP '${CODE:-no response}')." >&2
  echo "         Check:" >&2
  echo "         kubectl -n $NS get pods,svc" >&2
fi

echo "v12 environment ready"
echo "   - namespace $NS: Deployment $DEP (labels app=$DEP) and Service $DEP on port 80"
echo "   - namespace $CLI: labelled name=$CLI, holds pod probe"
echo "   - namespace $OTH: unlabelled, holds pod probe"
echo "   - no NetworkPolicy exists yet, so the api is reachable from anywhere"
echo "   - Task: write the policy that lets the client namespace in, and nothing else"
