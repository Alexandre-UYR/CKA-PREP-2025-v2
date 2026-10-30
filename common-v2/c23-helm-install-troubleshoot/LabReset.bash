#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

NS=webapps
RELEASE=broken
CHARTS=/tmp/cka-lab/charts
WORK="$CHARTS/broken-chart"
PRISTINE="$CHARTS/.pristine-broken-chart"

# Uninstall the release before the namespace goes: the release's own secret
# lives in the namespace, and a release that is still installed would make the
# next `helm install` fail with "cannot re-use a name that is still in use".
if helm status "$RELEASE" -n "$NS" >/dev/null 2>&1; then
  helm uninstall "$RELEASE" -n "$NS" >/dev/null 2>&1 || true
fi

# The namespace holds the Deployment the chart created and everything the
# candidate may have added to it.
k delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# Put the chart back the way the setup found it: the candidate edited the
# working copy, the pristine copy was never touched.
rm -rf "$WORK"
if [ -d "$PRISTINE" ]; then
  cp -R "$PRISTINE" "$WORK"
fi

echo "c23 reset: release $RELEASE uninstalled, namespace $NS removed, and the"
echo "            chart restored to its broken state"
