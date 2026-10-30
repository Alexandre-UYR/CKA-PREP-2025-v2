#!/bin/bash
set -e

# Pre-state for c14: three namespaces, a Deployment and Service to protect, the
# namespace label the policy has to select on, and a place to run probes from
# on both sides of the policy.
#
# The `name=frontend` label is the hook the candidate's namespaceSelector needs:
# a namespaceSelector can only pick namespaces out by their labels, so the
# setup removes the label and applies it again. A second run therefore leaves
# exactly the label the question started from.
NS_NETPOL=netpol
NS_FRONTEND=frontend
NS_OTHER=other

kubectl create namespace "$NS_NETPOL"   --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "$NS_FRONTEND" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "$NS_OTHER"    --dry-run=client -o yaml | kubectl apply -f -

# The label the policy will match on. Remove first, then apply, so the label is
# present exactly once and the setup is safe to re-run.
kubectl label namespace "$NS_FRONTEND" name- --overwrite >/dev/null 2>&1 || true
kubectl label namespace "$NS_FRONTEND" name=frontend --overwrite

# The workload that gets protected, and the Service that fronts it.
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: netpol
  labels:
    app: api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
        - name: api
          image: nginx
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: api
  namespace: netpol
spec:
  type: ClusterIP
  selector:
    app: api
  ports:
    - name: http
      port: 80
      targetPort: 80
      protocol: TCP
EOF

# A long-running probe pod in each client namespace, so the candidate and the
# grader both have somewhere to run curl from: one on the allowed side, one on
# the denied side.
for ns in "$NS_FRONTEND" "$NS_OTHER"; do
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tester
  namespace: $ns
  labels:
    app: tester
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tester
  template:
    metadata:
      labels:
        app: tester
    spec:
      containers:
        - name: curl
          image: curlimages/curl
          command: ["sleep","3600"]
EOF
done

# The api pods have to be up before any traffic test means anything. A failure
# here is a broken pre-state, not a wrong answer, so it is reported and not
# fatal.
kubectl -n "$NS_NETPOL" rollout status deploy/api --timeout=120s \
  || echo "   warning: the api deployment is not ready yet"

echo "✅ c14 environment ready"
echo "   - namespaces: $NS_NETPOL, $NS_FRONTEND (label name=frontend), $NS_OTHER"
echo "   - Deployment/Service: api (nginx, app=api) on port 80 in $NS_NETPOL"
echo "   - probe pods: curlimages/curl in $NS_FRONTEND and $NS_OTHER"
echo "   - Task: write a NetworkPolicy that lets only $NS_FRONTEND reach api:80"
