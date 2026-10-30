#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

NS=pki
LABDIR=/tmp/cka-lab
ISSUER_FILE="$LABDIR/issuer.yaml"
CRD_FILE="$LABDIR/cert-manager.crds.yaml"

# The namespace holds the Issuer, the Certificate and the Secret the
# controller wrote - deleting it removes all three.
k delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# The Issuer manifest is the file the candidate was handed, so it goes too.
rm -f "$ISSUER_FILE"

# ---------------------------------------------------------------------------
# NOT deleted on purpose:
#
#   - the cert-manager CRDs (certificates.cert-manager.io, issuers, and the
#     rest). They are CLUSTER-SCOPED, and deleting a CRD deletes every object
#     of that kind in the whole cluster - including the Certificate and the
#     Issuer of any other question that is running.
#   - the cert-manager controller Deployment, its ServiceAccount and its
#     ClusterRole/ClusterRoleBinding. They are part of the environment the
#     setup put there, and the next run of the setup re-uses them as they
#     are.
#
# The downloaded CRD manifest is left in place too, so that the setup can be
# re-run on a machine with no network access.
# ---------------------------------------------------------------------------

echo "x7 reset: namespace $NS removed, $ISSUER_FILE deleted"
echo "          (the cert-manager CRDs and the controller were left alone -"
echo "           the CRDs are cluster-scoped and must not be deleted)"
