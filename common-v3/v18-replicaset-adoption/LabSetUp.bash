#!/bin/bash
set -e

# v18 - Take the pods over from their old owner
#
# The pre-state is a Deployment that has been deleted with --cascade=orphan.
# That leaves its ReplicaSet behind, orphaned, still owning the two pods it
# made - and the two pods still Running. The Deployment itself is gone, so
# nothing is recreating or replacing them.
#
# The catch is that an orphaned ReplicaSet still CONTROLS its pods, and a
# ReplicaSet adopts a pod only when the pod has no controller. The old owner
# has to go (or be scaled to zero) before the new one can take over.
#
# The namespace is recreated on every run, so a Deployment left over from a
# previous attempt cannot answer the validation on its own.

NS=adopt
DEP=web

kubectl delete namespace "$NS" --ignore-not-found --timeout=120s
kubectl create namespace "$NS"

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEP
  namespace: $NS
  labels:
    app: $DEP
spec:
  replicas: 2
  selector:
    matchLabels:
      app: $DEP
  template:
    metadata:
      labels:
        app: $DEP
    spec:
      containers:
        - name: web
          image: nginx:1.25
          ports:
            - containerPort: 80
EOF

echo "Waiting for the Deployment's two pods to be Running..."
READY=""
i=0
while [ "$i" -lt 120 ]; do
  READY=$(kubectl -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null) || READY=""
  [ "$READY" = "2" ] && break
  sleep 3
  i=$((i+3))
done

# Remember which pods the candidate inherited, and their UIDs. The validator
# uses them to tell an ADOPTED pod from a replacement: a pod that was
# deleted and made again has a new UID.
PODLINE=""
for p in $(kubectl -n "$NS" get pods -l "app=$DEP" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  u=$(kubectl -n "$NS" get pod "$p" -o jsonpath='{.metadata.uid}' 2>/dev/null || true)
  PODLINE="${PODLINE}${p}=${u},"
done
kubectl -n "$NS" annotate namespace "$NS" "cka-lab/original-pods=$PODLINE" --overwrite >/dev/null

# Now delete the Deployment, but orphan what it owns: the ReplicaSet and the
# two pods survive, with the ReplicaSet still controlling them.
kubectl -n "$NS" delete deployment "$DEP" --cascade=orphan

echo "Waiting for the orphaned ReplicaSet and its pods to settle..."
RSNAME=""
RUNNING=""
i=0
while [ "$i" -lt 120 ]; do
  RSNAME=$(kubectl -n "$NS" get rs -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
             | grep "^${DEP}-" | head -1) || RSNAME=""
  RUNNING=$(kubectl -n "$NS" get pods -l "app=$DEP" \
              -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}' 2>/dev/null \
              | grep -c "^Running$" || true)
  if [ -n "$RSNAME" ] && [ "$RUNNING" = "2" ]; then break; fi
  sleep 3
  i=$((i+3))
done

RSREPLICAS=$(kubectl -n "$NS" get rs "$RSNAME" -o jsonpath='{.spec.replicas}' 2>/dev/null || true)
PODS=$(kubectl -n "$NS" get pods -l "app=$DEP" \
         -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.status.phase}{"  "}{.metadata.ownerReferences[0].name}{"\n"}{end}' 2>/dev/null || true)

echo "✅ v18 environment ready"
echo "   - namespace: $NS"
echo "   - Deployment $DEP: deleted, with --cascade=orphan"
echo "   - orphaned ReplicaSet: ${RSNAME:-<not found>} (replicas ${RSREPLICAS:-?})"
echo "   - the pods it left behind:"
printf '%s\n' "$PODS" | sed 's/^/       /'
echo "   - Task: create a ReplicaSet 'web-adopted' with 2 replicas that adopts"
echo "     those two pods - they have to be adopted, not replaced"

if [ -z "$RSNAME" ] || [ "$RUNNING" != "2" ]; then
  echo "   ⚠️  The orphaned ReplicaSet or its pods are not what they should be. Check:" >&2
  echo "      kubectl -n $NS get rs" >&2
  echo "      kubectl -n $NS get pods -o wide" >&2
fi
