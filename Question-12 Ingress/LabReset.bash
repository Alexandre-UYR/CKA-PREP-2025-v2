#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# --- the pre-state (namespace deletion removes the deployment, the Service and the Ingress) ---
k delete ns echo-sound --ignore-not-found --wait=false >/dev/null 2>&1 || true

# --- the candidate's optional /etc/hosts entry for example.org ---
# Back the file up first, then remove only the lines whose LAST field is the
# hostname, so nothing else in /etc/hosts is touched.
HOSTS=/etc/hosts
BAK=/tmp/cka-lab/hosts.q12.bak
mkdir -p /tmp/cka-lab
TMP=$(mktemp 2>/dev/null || echo /tmp/cka-lab/hosts.q12.tmp)

if [ -r "$HOSTS" ]; then
  cp "$HOSTS" "$BAK" 2>/dev/null || true
  awk -v n="example.org" '{ if (NF > 0 && $NF == n) next; print }' "$HOSTS" > "$TMP" 2>/dev/null
  if [ -w "$HOSTS" ]; then
    cat "$TMP" > "$HOSTS" 2>/dev/null
  elif sudo -n true 2>/dev/null; then
    sudo -n tee "$HOSTS" < "$TMP" >/dev/null 2>&1
  else
    echo "WARNING: $HOSTS is not writable and sudo is unavailable - remove the example.org line by hand."
  fi
else
  echo "WARNING: $HOSTS could not be read - remove the example.org line by hand."
fi
rm -f "$TMP" 2>/dev/null

echo "Q12 reset: namespace echo-sound deleted (deployment echo, Service echo-service and"
echo "             Ingress echo went with it) and any /etc/hosts line for example.org"
echo "             removed. A backup of /etc/hosts is at $BAK"
