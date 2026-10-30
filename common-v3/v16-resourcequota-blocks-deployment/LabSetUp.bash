#!/bin/bash
set -e

# v16 - The API server that says no
#
# The pre-state is a namespace whose ResourceQuota demands CPU and memory
# requests AND limits. A workload that declares none of them is refused at
# admission time: the API server will not create the Pod, so nothing is
# persisted and there is no object to look at afterwards - only the error.
#
# The setup creates such a workload, captures the refusal and removes the
# attempt again, so the candidate starts from the refusal itself and has to
# write a manifest the API server will accept.
#
# The namespace and everything in it are recreated on every run, so the setup
# is idempotent and the starting state is always the same.

NS=quota
QUOTA=compute-quota
LR=defaults
DEP=app

kubectl delete namespace "$NS" --ignore-not-found --wait=true --timeout=120s >/dev/null 2>&1 || true
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: $QUOTA
  namespace: $NS
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 4Gi
    limits.cpu: "2"
    limits.memory: 4Gi
EOF

# The attempt: a Deployment with no resources at all.
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
EOF

echo "Waiting for the API server to refuse the Pod..."
RSNAME=$(kubectl -n "$NS" get rs -l "app=$DEP" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || RSNAME=""
FAILMSG=""
i=0
while [ "$i" -lt 60 ]; do
  if [ -n "$RSNAME" ]; then
    FAILMSG=$(kubectl -n "$NS" get rs "$RSNAME" \
              -o jsonpath='{.status.conditions[?(@.type=="ReplicaFailure")].message}' 2>/dev/null) || FAILMSG=""
  fi
  [ -n "$FAILMSG" ] && break
  sleep 2
  i=$((i+2))
done

# The attempt has served its purpose: the refusal is the pre-state, and the
# candidate writes the manifest that gets accepted.
kubectl -n "$NS" delete deploy "$DEP" --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1 || true

# The LimitRange supplies memory defaults, so a manifest that declares the
# CPU values and leaves the memory to the namespace is admitted too.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: LimitRange
metadata:
  name: $LR
  namespace: $NS
spec:
  limits:
    - type: Container
      defaultRequest:
        memory: 512Mi
      default:
        memory: 1Gi
EOF

echo "✅ v16 environment ready"
echo "   - namespace: $NS"
echo "   - ResourceQuota: $QUOTA"
echo "   -   requests.cpu 2, requests.memory 4Gi, limits.cpu 2, limits.memory 4Gi"
echo "   -   every Pod in this namespace must declare all four"
echo "   - LimitRange: $LR (defaultRequest memory 512Mi, default memory 1Gi)"
echo "   - the setup tried a Deployment with no resources. The API server said:"
echo "     ${FAILMSG:-<no refusal captured>}"
echo "   - Task: create a Deployment '$DEP' the API server accepts, and make it run"

if [ -z "$FAILMSG" ]; then
  echo "   ⚠️  The refusal was not captured. Check the events:" >&2
  echo "      kubectl -n $NS describe rs -l app=$DEP" >&2
fi
