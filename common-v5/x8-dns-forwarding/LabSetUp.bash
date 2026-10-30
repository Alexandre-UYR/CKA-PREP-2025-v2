#!/bin/bash
set -e

# x8 - Cluster names work, the internet does not
#
# The pre-state is a healthy CoreDNS whose Corefile has lost its `forward`
# directive. The `kubernetes` plugin still serves cluster service names, and
# nothing is forwarded to the node's resolver, so external names fail.
#
# The break has to take the WHOLE `forward` directive with it, block included:
# the stock Corefile reads
#
#     forward . /etc/resolv.conf {
#        max_concurrent 1000
#     }
#
# and leaving the braces behind would make CoreDNS fail to parse its own
# configuration and crash-loop, which is a different (and much louder)
# symptom than the one the task describes.
#
# The original Corefile is saved outside the cluster so that the reset can put
# it back. The setup restores that copy FIRST, so running the setup twice can
# never save an already-broken ConfigMap as the "original".

NS=dns
NS_SYS=kube-system
LABDIR=/tmp/cka-lab
ORIG_CF="$LABDIR/x8.corefile"
BROKEN_CF="$LABDIR/x8.corefile.broken"
PROBE=x8probe

mkdir -p "$LABDIR"

kubectl delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

# --- find CoreDNS, by name or by label ---
CM_NAME="coredns"
kubectl -n "$NS_SYS" get configmap "$CM_NAME" >/dev/null 2>&1 || \
  CM_NAME=$(kubectl -n "$NS_SYS" get configmap -l k8s-app=kube-dns -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
DEP_NAME="coredns"
kubectl -n "$NS_SYS" get deployment "$DEP_NAME" >/dev/null 2>&1 || \
  DEP_NAME=$(kubectl -n "$NS_SYS" get deployment -l k8s-app=kube-dns -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [ -z "$CM_NAME" ] || [ -z "$DEP_NAME" ]; then
  echo "error: no CoreDNS ConfigMap and Deployment found in $NS_SYS." >&2
  echo "       This question needs CoreDNS to be installed." >&2
  exit 1
fi

# --- 1. restore the original if we have one, so a re-run starts from health ---
if [ -s "$ORIG_CF" ]; then
  echo "Restoring the original Corefile from $ORIG_CF..."
  kubectl -n "$NS_SYS" create configmap "$CM_NAME" --from-file=Corefile="$ORIG_CF" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n "$NS_SYS" rollout restart "deploy/$DEP_NAME" >/dev/null 2>&1 || true
  kubectl -n "$NS_SYS" rollout status "deploy/$DEP_NAME" --timeout=180s >/dev/null 2>&1 || true
fi

# --- 2. save the original Corefile ---
kubectl -n "$NS_SYS" get configmap "$CM_NAME" -o jsonpath='{.data.Corefile}' > "$ORIG_CF" 2>/dev/null || true
if [ ! -s "$ORIG_CF" ]; then
  echo "error: the ConfigMap $CM_NAME has no Corefile - cannot break CoreDNS." >&2
  exit 1
fi

# --- 3. break the Corefile: remove the forward directive and its block ---
awk '
function indent(s,   m){ match(s, /[^ ]/); return RSTART ? RSTART - 1 : length(s) }
{
  if (skip) {
    if ($0 ~ /^[[:space:]]*$/) next
    i = indent($0)
    if (i > skipind) next                          # inside the block of the directive
    if ($0 ~ /^[[:space:]]*}/) { skip = 0; next }  # the closing brace of the block
    skip = 0
  }
  if ($0 ~ /^[[:space:]]*forward[[:space:]]/) { skip = 1; skipind = indent($0); next }
  print
}
' "$ORIG_CF" > "$BROKEN_CF" || true

if cmp -s "$ORIG_CF" "$BROKEN_CF"; then
  echo "error: no 'forward' directive in the Corefile - cannot break CoreDNS." >&2
  exit 1
fi
if grep -q 'kubernetes' "$BROKEN_CF"; then
  echo "The kubernetes plugin is still in the broken Corefile - cluster names keep working."
else
  echo "WARNING: the broken Corefile has no 'kubernetes' plugin either." >&2
  echo "         Cluster service names will not resolve, and the symptom the" >&2
  echo "         task describes will not be the one the candidate sees." >&2
fi

kubectl -n "$NS_SYS" create configmap "$CM_NAME" --from-file=Corefile="$BROKEN_CF" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# --- 4. make CoreDNS pick the broken Corefile up ---
# CoreDNS reads its configuration at start-up, so the pods have to be
# restarted for the broken Corefile to take effect.
kubectl -n "$NS_SYS" rollout restart "deploy/$DEP_NAME" >/dev/null
kubectl -n "$NS_SYS" rollout status "deploy/$DEP_NAME" --timeout=180s >/dev/null 2>&1 || true

# --- 5. wait until CoreDNS is actually serving again ---
i=0
READY=""
while [ "$i" -lt 30 ]; do
  READY=$(kubectl -n "$NS_SYS" get deploy "$DEP_NAME" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
  case "$READY" in ''|*[!0-9]*) READY=0;; esac
  if [ "$READY" -ge 1 ]; then break; fi
  i=$((i+1)); sleep 2
done
if [ "${READY:-0}" -ge 1 ]; then
  echo "CoreDNS is up again with the broken Corefile ($READY ready replica)."
else
  echo "WARNING: CoreDNS did not come back up. Check:" >&2
  echo "         kubectl -n $NS_SYS get pods -l k8s-app=kube-dns" >&2
  echo "         kubectl -n $NS_SYS logs deploy/$DEP_NAME" >&2
fi

# --- 6. confirm the symptom: cluster names work, external names do not ---
probe_dns(){
  # Runs nslookup for the given name in a throwaway pod and prints the output.
  local name=$1
  kubectl -n "$NS" delete pod "$PROBE" --ignore-not-found --wait=true >/dev/null 2>&1 || true
  kubectl -n "$NS" run "$PROBE" --restart=Never --image=busybox:1.36 -- nslookup "$name" >/dev/null 2>&1 || true
  local phase="" j=0
  while [ "$j" -lt 30 ]; do
    phase=$(kubectl -n "$NS" get pod "$PROBE" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    case "$phase" in Succeeded|Failed) break;; esac
    j=$((j+1)); sleep 2
  done
  kubectl -n "$NS" logs "$PROBE" 2>/dev/null || true
  kubectl -n "$NS" delete pod "$PROBE" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

INTERNAL=example
CLUSTER_NAME=kubernetes.default.svc.cluster.local
EXT_NAME=example.com

echo "Checking the symptom: a cluster name, and an external name..."
CLUSTER_OUT=$(probe_dns "$CLUSTER_NAME")
EXT_OUT=$(probe_dns "$EXT_NAME")

CLUSTER_OK=0
if printf '%s\n' "$CLUSTER_OUT" | grep -E '^Address:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*$' >/dev/null 2>&1; then
  CLUSTER_OK=1
fi
EXT_OK=0
if printf '%s\n' "$EXT_OUT" | grep -E '^Address:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*$' >/dev/null 2>&1; then
  EXT_OK=1
fi

if [ "$CLUSTER_OK" = "1" ]; then
  echo "   - $CLUSTER_NAME resolves (as it should)"
else
  echo "   - WARNING: $CLUSTER_NAME does not resolve either." >&2
  echo "     The symptom the task describes needs cluster names to keep working." >&2
fi

if [ "$EXT_OK" = "0" ]; then
  echo "   - $EXT_NAME does not resolve (the broken state, as the task describes)"
else
  echo "   - WARNING: $EXT_NAME still resolves." >&2
  echo "     Either the node's resolver answers through another path, or the" >&2
  echo "     cluster has no outbound DNS problem to begin with." >&2
fi

echo "✅ x8 environment ready"
echo "   - namespace: $NS"
echo "   - CoreDNS ConfigMap: $NS_SYS/$CM_NAME (its Corefile has no forward directive)"
echo "   - CoreDNS Deployment: $NS_SYS/$DEP_NAME ($READY ready replica)"
echo "   - original Corefile saved at: $ORIG_CF"
echo "   - Task: find out why cluster names resolve and external names do not,"
echo "     put the forwarding back, restart CoreDNS so it picks the change up,"
echo "     and prove both kinds of resolution from a pod"
