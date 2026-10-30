#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

NS=apps
RELEASE=hello
CHART_ROOT=/tmp/cka-lab/charts
WORK="$CHART_ROOT/hello-world"
PRISTINE="$CHART_ROOT/.pristine-hello-world"
VALUES=/root/hello-values.yaml

# Uninstall the release before the namespace goes: the release's own secret
# lives in the namespace, and a release that is still installed would make
# the next `helm install` fail with "cannot re-use a name that is still in
# use".
if command -v helm >/dev/null 2>&1; then
  if helm status "$RELEASE" -n "$NS" >/dev/null 2>&1; then
    helm uninstall "$RELEASE" -n "$NS" >/dev/null 2>&1 || true
  fi
fi

# The namespace holds the Deployment and the Service the release created.
k delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

# Put the chart back the way the setup found it: the candidate may have
# edited the working copy, and the pristine copy was never touched.
rm -rf "$WORK"
if [ -d "$PRISTINE" ]; then
  cp -R "$PRISTINE" "$WORK"
fi

# The values file is the candidate's output, not part of the pre-state: it
# is removed so the next attempt starts from nothing.
rm -f "$VALUES"

echo "w10 reset: release $RELEASE uninstalled, namespace $NS removed, the"
echo "           chart restored and $VALUES removed"
