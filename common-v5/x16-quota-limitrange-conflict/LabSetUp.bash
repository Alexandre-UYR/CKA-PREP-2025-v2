#!/bin/bash
set -e

# x16 - Two rules that contradict each other
#
# The namespace carries a LimitRange whose DEFAULTS are larger than the
# ResourceQuota's CEILINGS. The LimitRanger admission plugin fills in the
# missing requests and limits of every container that does not state its own,
# and the ResourceQuota plugin then refuses the result. Nothing can be
# created - not even a Pod that asks for nothing.
#
# Both objects must survive the exercise unchanged, so the setup records
# their specs and the grader compares them against the live objects.

NS=conflict
QUOTA=tight
LR=defaults
LABDIR=/tmp/cka-lab

mkdir -p "$LABDIR"

kubectl delete namespace "$NS" --ignore-not-found --wait=true --timeout=120s >/dev/null 2>&1 || true
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: LimitRange
metadata:
  name: $LR
  namespace: $NS
spec:
  limits:
    - type: Container
      default:
        cpu: 2
        memory: 4Gi
      defaultRequest:
        cpu: 1
        memory: 2Gi
EOF

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: $QUOTA
  namespace: $NS
spec:
  hard:
    limits.cpu: "1"
    limits.memory: 1Gi
    requests.cpu: 500m
    requests.memory: 512Mi
EOF

# ---------------------------------------------------------------------------
# Record the specs of both objects, so the grader can prove that neither of
# them was changed. The values are read back from the API server, so the
# file holds exactly what is stored.
# ---------------------------------------------------------------------------
{
  echo "quota.hard.limits.cpu=$(kubectl -n "$NS" get resourcequota "$QUOTA" -o jsonpath='{.spec.hard.limits\.cpu}')"
  echo "quota.hard.limits.memory=$(kubectl -n "$NS" get resourcequota "$QUOTA" -o jsonpath='{.spec.hard.limits\.memory}')"
  echo "quota.hard.requests.cpu=$(kubectl -n "$NS" get resourcequota "$QUOTA" -o jsonpath='{.spec.hard.requests\.cpu}')"
  echo "quota.hard.requests.memory=$(kubectl -n "$NS" get resourcequota "$QUOTA" -o jsonpath='{.spec.hard.requests\.memory}')"
  echo "limitrange.type=$(kubectl -n "$NS" get limitrange "$LR" -o jsonpath='{.spec.limits[0].type}')"
  echo "limitrange.default.cpu=$(kubectl -n "$NS" get limitrange "$LR" -o jsonpath='{.spec.limits[0].default.cpu}')"
  echo "limitrange.default.memory=$(kubectl -n "$NS" get limitrange "$LR" -o jsonpath='{.spec.limits[0].default.memory}')"
  echo "limitrange.defaultRequest.cpu=$(kubectl -n "$NS" get limitrange "$LR" -o jsonpath='{.spec.limits[0].defaultRequest.cpu}')"
  echo "limitrange.defaultRequest.memory=$(kubectl -n "$NS" get limitrange "$LR" -o jsonpath='{.spec.limits[0].defaultRequest.memory}')"
} > "$LABDIR/x16.before"

# ---------------------------------------------------------------------------
# Prove that the pre-state really is the broken state: a Pod that states no
# resources at all has to be refused.
# ---------------------------------------------------------------------------
if cat <<EOF | kubectl apply -f - > "$LABDIR/x16.probe.log" 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: default-shape
  namespace: $NS
spec:
  containers:
    - name: app
      image: busybox:1.28
      command: ["sh", "-c", "sleep 3600"]
EOF
then
  echo "WARNING: a Pod with no resources of its own was accepted. The pre-state is not" >&2
  echo "         what the task describes. Removing it again." >&2
  kubectl -n "$NS" delete pod default-shape --ignore-not-found >/dev/null 2>&1 || true
else
  echo "As expected, the API server refuses a Pod that states no resources:"
  sed 's/^/    /' "$LABDIR/x16.probe.log" | head -4
fi

echo "✅ x16 environment ready"
echo "   - namespace: $NS"
echo "   - LimitRange $LR: default cpu=2 memory=4Gi, defaultRequest cpu=1 memory=2Gi"
echo "   - ResourceQuota $QUOTA: limits.cpu=1 limits.memory=1Gi requests.cpu=500m requests.memory=512Mi"
echo "   - the two objects' specs are recorded in $LABDIR/x16.before"
echo "   - Task: create a Pod 'fits' that the API server accepts, without touching the"
echo "     quota or the LimitRange"

echo
echo "   The limits the quota allows, per pod:"
echo "     requests.cpu    <= 500m"
echo "     requests.memory <= 512Mi"
echo "     limits.cpu      <= 1"
echo "     limits.memory   <= 1Gi"
