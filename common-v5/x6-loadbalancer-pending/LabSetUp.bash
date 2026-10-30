#!/bin/bash
set -e

# x6 - The Service that will never get an address
#
# The pre-state is a Service of type LoadBalancer on a cluster that has no
# load-balancer implementation (kind, a plain minikube cluster, a bare kubeadm
# cluster). Such a Service stays `pending` for ever: nothing in the cluster
# gives it an address. The point of the question is to notice that, and to
# publish the Service the other way round - a NodePort on the node's own IP.
#
# The setup records the Service's UID, because the task says to edit the
# Service rather than replace it, and the grader compares the UID.
#
# The setup also works out whether this cluster has any load-balancer
# implementation at all, and prints which case it is, so that nobody has to
# guess why the Service is pending.

NS=edge
DEP=site
SVC=public
LABDIR=/tmp/cka-lab
UIDFILE="$LABDIR/x6.svc.uid"

mkdir -p "$LABDIR"

# Start from a clean pre-state: a Service left over from an earlier attempt
# would already have the wrong type, and the UID check would be meaningless.
kubectl delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

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
        - name: nginx
          image: nginx:1.25
          ports:
            - containerPort: 80
              protocol: TCP
EOF

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: $SVC
  namespace: $NS
  annotations:
    external-dns.alpha.kubernetes.io/hostname: site.example.com
spec:
  type: LoadBalancer
  selector:
    app: $DEP
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
EOF

echo "Waiting for the Deployment to be available..."
kubectl -n "$NS" rollout status deployment/"$DEP" --timeout=180s

# Remember the Service's UID: the fix must be an edit, not a replacement.
kubectl -n "$NS" get svc "$SVC" -o jsonpath='{.metadata.uid}' > "$UIDFILE" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Does this cluster have any load-balancer implementation?
#
# Two signals are checked:
#   1. an external IP on any LoadBalancer Service in the cluster - if some
#      other Service got an address, something out there hands them out;
#   2. a `service-controller` in the kube-controller-manager's flags, or a
#      --cloud-provider flag, which means a cloud controller manager is
#      configured to do it.
# If neither is there, this cluster cannot give a LoadBalancer Service an
# address, and the Service stays pending for ever.
# ---------------------------------------------------------------------------
echo "Checking whether this cluster has any load-balancer implementation..."

LB_CASE="none"
LB_WHY="no load-balancer implementation was found on this cluster"

LBSVC=$(kubectl get svc --all-namespaces -o go-template='{{range .items}}{{if eq .spec.type "LoadBalancer"}}{{.metadata.namespace}}/{{.metadata.name}}{{"\n"}}{{end}}{{end}}' 2>/dev/null || true)
LBEXT=$(kubectl get svc --all-namespaces -o go-template='{{range .items}}{{if eq .spec.type "LoadBalancer"}}{{range .status.loadBalancer.ingress}}{{.ip}}{{.hostname}}{{"\n"}}{{end}}{{end}}{{end}}' 2>/dev/null | grep -v '^[[:space:]]*$' | head -1 || true)
if [ -n "$LBEXT" ]; then
  LB_CASE="external-ip"
  LB_WHY="a LoadBalancer Service on this cluster already has the address $LBEXT"
fi

KCM=$(kubectl -n kube-system get pods -o jsonpath='{range .items[*]}{.metadata.name}{" "}{range .spec.containers[*]}{.command}{" "}{.args}{" "}{end}{"\n"}{end}' 2>/dev/null | grep -i 'controller-manager' || true)
KCMARGS=$(printf '%s' "$KCM" | tr ' ' '\n' | grep -v '^$' || true)

if [ "$LB_CASE" = "none" ]; then
  if printf '%s\n' "$KCMARGS" | grep -q 'service-controller' && ! printf '%s\n' "$KCMARGS" | grep -q -- '-service-controller'; then
    LB_CASE="service-controller-flag"
    LB_WHY="the kube-controller-manager is started with a service-controller"
  elif printf '%s\n' "$KCMARGS" | grep -Eq -- '--cloud-provider=.+'; then
    LB_CASE="cloud-provider-flag"
    LB_WHY="the kube-controller-manager is started with a cloud provider"
  fi
fi

echo "   - load-balancer implementation: $LB_CASE ($LB_WHY)"
if [ -n "$LBSVC" ]; then
  echo "   - LoadBalancer Services on the cluster:"
  printf '%s\n' "$LBSVC" | sed 's/^/       /'
fi

# ---------------------------------------------------------------------------
# Wait to see whether the Service is given an address after all. On a cluster
# with no implementation it stays pending; on one that has one, it gets an
# address and the task's premise does not hold - the setup says so rather
# than pretending.
# ---------------------------------------------------------------------------
echo "Watching the Service for an external address..."
i=0
EXTIP=""
while [ "$i" -lt 15 ]; do
  EXTIP=$(kubectl -n "$NS" get svc "$SVC" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  [ -n "$EXTIP" ] && break
  i=$((i+1)); sleep 2
done

EP=$(kubectl -n "$NS" get endpoints "$SVC" -o jsonpath='{range .subsets[*].addresses[*]}{.ip}{"\n"}{end}' 2>/dev/null | grep -c '[0-9]' || true)

echo "✅ x6 environment ready"
echo "   - namespace: $NS"
echo "   - Deployment: $DEP (nginx:1.25, 2 replicas, labels app=$DEP)"
echo "   - Service: $SVC (type LoadBalancer, port 80 -> targetPort 80, selector app=$DEP)"
echo "   - annotation: external-dns.alpha.kubernetes.io/hostname: site.example.com"
echo "   - Service endpoints: ${EP:-0} (the back end is fine - only the address is missing)"
if [ -n "$EXTIP" ]; then
  echo "   - external IP: $EXTIP"
  echo "   - WARNING: this cluster DOES hand out load-balancer addresses, so the"
  echo "     'it stays pending' part of the task does not apply here. The task is"
  echo "     still solvable and the grading is the same."
else
  echo "   - external IP: <pending> (expected: $LB_WHY)"
fi
echo "   - Task: change the Service to a NodePort on 30080 so it can be reached"
echo "     from outside the cluster, edit it rather than replace it, and prove it"
echo "     works from inside the cluster"

# Warn early if the nodePort the task fixes is already taken, so a candidate
# is not left guessing why their Service will not take the port.
if kubectl get svc --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{" "}{range .spec.ports[*]}{.nodePort}{" "}{end}{"\n"}{end}' 2>/dev/null | grep -q '30080'; then
  echo "   ⚠️  nodePort 30080 is already in use by another Service on this cluster." >&2
fi
