#!/bin/bash
set -e

# Pre-state for c16: a healthy cluster with one empty namespace, and a CoreDNS
# Corefile that has been broken on purpose.
#
# The break is a rename of the `kubernetes` plugin. CoreDNS parses its Corefile
# at start-up and exits when it meets a plugin it does not know, so the CoreDNS
# pods go into CrashLoopBackOff and cluster service names stop resolving.
#
# The original ConfigMap is copied outside the cluster so that the reset can
# put it back. The setup restores that copy FIRST, so running the setup twice
# can never save an already-broken ConfigMap as the "original".
LAB_DIR=/tmp/cka-lab
CM_BACKUP="$LAB_DIR/c16.coredns.cm"      # the original ConfigMap, verbatim
CF_BACKUP="$LAB_DIR/c16.corefile"        # the original Corefile text
BROKEN_CF="$LAB_DIR/c16.corefile.broken" # what gets installed in its place
NS=dns
NS_SYS=kube-system
CM=coredns
DEP=coredns
BROKEN=kubernetesBROKEN

mkdir -p "$LAB_DIR"

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

# The question is about CoreDNS, so CoreDNS has to be here.
if ! kubectl -n "$NS_SYS" get configmap "$CM" >/dev/null 2>&1; then
  echo "error: the ConfigMap $CM was not found in $NS_SYS" >&2
  exit 1
fi
if ! kubectl -n "$NS_SYS" get deploy "$DEP" >/dev/null 2>&1; then
  echo "error: the Deployment $DEP was not found in $NS_SYS" >&2
  exit 1
fi

# --- 1. restore the original if we have one, so a re-run starts from health ---
if [ -s "$CF_BACKUP" ]; then
  kubectl -n "$NS_SYS" create configmap "$CM" --from-file=Corefile="$CF_BACKUP" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n "$NS_SYS" rollout restart "deploy/$DEP" >/dev/null 2>&1 || true
  kubectl -n "$NS_SYS" rollout status "deploy/$DEP" --timeout=120s >/dev/null 2>&1 || true
fi

# --- 2. save the original ConfigMap and its Corefile ---
kubectl -n "$NS_SYS" get configmap "$CM" -o yaml > "$CM_BACKUP"
kubectl -n "$NS_SYS" get configmap "$CM" -o jsonpath='{.data.Corefile}' > "$CF_BACKUP"

# --- 3. break the Corefile: rename the kubernetes plugin ---
# `kubernetes` followed by a non-letter is the plugin name and nothing else.
sed 's/kubernetes\([^a-zA-Z]\)/'"$BROKEN"'\1/g' "$CF_BACKUP" > "$BROKEN_CF"
if cmp -s "$CF_BACKUP" "$BROKEN_CF"; then
  echo "error: no 'kubernetes' plugin found in the Corefile - cannot break CoreDNS" >&2
  exit 1
fi

kubectl -n "$NS_SYS" create configmap "$CM" --from-file=Corefile="$BROKEN_CF" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# --- 4. make CoreDNS pick the broken Corefile up ---
# CoreDNS reads its configuration at start-up, so the pods have to be
# restarted for the broken Corefile to take effect.
kubectl -n "$NS_SYS" rollout restart "deploy/$DEP" >/dev/null

# --- 5. confirm the breakage took ---
i=0
BROKE=0
while [ $i -lt 12 ]; do
  NOTREADY=$(kubectl -n "$NS_SYS" get pods -l k8s-app=kube-dns \
    -o jsonpath='{range .items[*]}{range .status.conditions[?(@.type=="Ready")]}{.status}{"\n"}{end}{end}' 2>/dev/null \
    | grep -c '^False' || true)
  if [ "${NOTREADY:-0}" -gt 0 ]; then BROKE=1; break; fi
  i=$((i+1)); sleep 5
done

echo "✅ c16 environment ready"
echo "   - namespace: $NS"
echo "   - CoreDNS ConfigMap $CM/$NS_SYS: Corefile broken (the kubernetes plugin renamed to $BROKEN)"
if [ "$BROKE" = "1" ]; then
  echo "   - CoreDNS pods are not ready (CrashLoopBackOff)"
else
  echo "   - WARNING: the CoreDNS pods still look ready - the Corefile did not take effect"
  echo "   - WARNING: check 'kubectl -n $NS_SYS get pods -l k8s-app=kube-dns' and the Corefile"
fi
echo "   - original ConfigMap saved at: $CM_BACKUP"
echo "   - Task: find out why cluster DNS stopped working and fix it"
