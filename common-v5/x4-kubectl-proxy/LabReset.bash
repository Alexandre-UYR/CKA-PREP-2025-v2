#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

LABDIR=/tmp/cka-lab
NAMELIST="$LABDIR/x4.namespaces"

# The response the candidate was supposed to produce.
rm -f /root/namespaces.json "$HOME/namespaces.json"

# The namespaces the setup created.
NSLIST=""
if [ -f "$NAMELIST" ]; then
  NSLIST=$(tr '\n' ' ' < "$NAMELIST" | tr -s ' ')
fi
if [ -z "$NSLIST" ]; then
  NSLIST="cka-proxy-alpha cka-proxy-beta"
fi

for NS in $NSLIST; do
  [ -n "$NS" ] || continue
  k delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
done

rm -f "$NAMELIST"

echo "x4 reset: /root/namespaces.json removed, the namespaces the setup created deleted"
