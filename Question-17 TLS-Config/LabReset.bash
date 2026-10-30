#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

# --- the pre-state (namespace deletion removes the deployment, the ConfigMap, the Secret and the Service) ---
k delete ns nginx-static --ignore-not-found --wait=false >/dev/null 2>&1 || true

# --- the candidate's /etc/hosts entry ---
# Back the file up first, then remove only the lines whose LAST field is the
# hostname, so nothing else in /etc/hosts is touched.
HOSTS=/etc/hosts
BAK=/tmp/cka-lab/hosts.q17.bak
mkdir -p /tmp/cka-lab
TMP=$(mktemp 2>/dev/null || echo /tmp/cka-lab/hosts.q17.tmp)

if [ -r "$HOSTS" ]; then
  cp "$HOSTS" "$BAK" 2>/dev/null || true
  awk -v n="ckaquestion.k8s.local" '{ if (NF > 0 && $NF == n) next; print }' "$HOSTS" > "$TMP" 2>/dev/null
  if [ -w "$HOSTS" ]; then
    cat "$TMP" > "$HOSTS" 2>/dev/null
  elif sudo -n true 2>/dev/null; then
    sudo -n tee "$HOSTS" < "$TMP" >/dev/null 2>&1
  else
    echo "WARNING: $HOSTS is not writable and sudo is unavailable - remove the ckaquestion.k8s.local line by hand."
  fi
else
  echo "WARNING: $HOSTS could not be read - remove the ckaquestion.k8s.local line by hand."
fi
rm -f "$TMP" 2>/dev/null

# --- the state files the setup wrote ---
rm -f /tmp/cka-lab/q17.setup.time /tmp/cka-lab/q17.pod.before \
      /tmp/cka-lab/q17.tls.crt /tmp/cka-lab/q17.tls.key 2>/dev/null || true

echo "Q17 reset: namespace nginx-static deleted (deployment, ConfigMap, Secret and"
echo "             Service went with it), the /etc/hosts line for ckaquestion.k8s.local"
echo "             removed and the q17 state files deleted."
echo "             A backup of /etc/hosts is at $BAK"
