#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

ROOT=/tmp/cka-lab/kustomize
BASE="$ROOT/base"
PRISTINE="$ROOT/.pristine-base"

# The namespace holds the Deployment and the Service the dev overlay was
# applied to. Deleting it removes both.
k delete namespace dev --ignore-not-found --timeout=120s >/dev/null

# The overlays live on disk, not in the cluster: the dev overlay the candidate
# fixed and the prod overlay they wrote both go.
rm -rf "$ROOT/overlays"

# The base is restored from the pristine copy, so a candidate who edited the
# base to make their patch work does not leave that edit behind.
if [ -d "$PRISTINE" ]; then
  rm -rf "$BASE"
  cp -R "$PRISTINE" "$BASE"
  BASE_STATE="restored from $PRISTINE"
else
  BASE_STATE="left as it is (no pristine copy found)"
fi

echo "w15 reset: namespace dev removed, $ROOT/overlays deleted, base $BASE_STATE"
