#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

NS=gw
GATEWAY=web-gateway
ROUTE=web-route
DIR=/tmp/cka-lab/gateway

# The answer: the Gateway and the HTTPRoute the candidate created.
k -n "$NS" delete gateway "$GATEWAY" --ignore-not-found >/dev/null 2>&1
k -n "$NS" delete httproute "$ROUTE" --ignore-not-found >/dev/null 2>&1

# The CRDs the candidate installed. The pre-state has the `gatewayclasses` CRD
# and the GatewayClass, but not the two the Gateway and the HTTPRoute need, so
# the two go back.
k delete crd gateways.gateway.networking.k8s.io --ignore-not-found >/dev/null 2>&1
k delete crd httproutes.gateway.networking.k8s.io --ignore-not-found >/dev/null 2>&1

# The namespace holds the Ingress, the Deployment, the Service and the Secret.
k delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null

# Put the pre-state back from the copies the setup kept, so the Ingress is
# there again - a copy, not the original object, which is why it comes back
# with a new UID.
RESTORED="nothing (no copies in $DIR)"
if [ -d "$DIR" ]; then
  k create namespace "$NS" --dry-run=client -o yaml | k apply -f - >/dev/null 2>&1
  RESTORED=""
  for f in deployment.yaml service.yaml secret.yaml ingress.yaml gatewayclass.yaml; do
    if [ -f "$DIR/$f" ]; then
      if k apply -f "$DIR/$f" >/dev/null 2>&1; then
        RESTORED="$RESTORED $f"
      fi
    fi
  done
  RESTORED="${RESTORED:-nothing}"
fi

echo "w17 reset: Gateway and HTTPRoute deleted, namespace $NS recreated,"
echo "          the pre-state restored from the copies:$RESTORED"
echo "          the gateways and httproutes CRDs removed again; the copies in"
echo "          $DIR are kept so the next reset can use them too"
