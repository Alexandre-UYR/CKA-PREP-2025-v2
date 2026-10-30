#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

STATE=/tmp/cka-lab
TOKENS_FILE="$STATE/c7.tokens"
JOIN_FILE=/root/kubeadm-join.sh

# ------------------------------------------------ 1. the new tokens are gone --

# The tokens that existed before the exercise are in the state file, so
# whatever is in the list now that is not in that file was created by the
# candidate - and those are the ones to delete.
if command -v kubeadm >/dev/null 2>&1; then
  BEFORE=""
  if [ -f "$TOKENS_FILE" ]; then
    BEFORE=$(cat "$TOKENS_FILE" 2>/dev/null || true)
  fi
  NOW=$(kubeadm token list 2>/dev/null | awk 'NF>0 {print $1}' | grep -E '^[a-z0-9]{6}$' || true)
  for t in $NOW; do
    if ! printf '%s\n' "$BEFORE" | grep -qx "$t"; then
      if kubeadm token delete "$t" >/dev/null 2>&1; then
        echo "c7 reset: deleted bootstrap token $t"
      else
        echo "c7 reset: could not delete bootstrap token $t" >&2
      fi
    fi
  done
else
  echo "c7 reset: kubeadm is not installed here, so no tokens were deleted" >&2
fi

# --------------------------------------------------- 2. the join file is gone --

if [ -f "$JOIN_FILE" ]; then
  if rm -f "$JOIN_FILE" 2>/dev/null; then
    echo "c7 reset: removed $JOIN_FILE"
  else
    echo "c7 reset: WARNING - could not remove $JOIN_FILE (it needs root)" >&2
  fi
fi

# ----------------------------------------------------- 3. the state file -----

rm -f "$TOKENS_FILE" 2>/dev/null || true

echo "c7 reset: done"
