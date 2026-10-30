#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }
G='\033[32m'; R='\033[31m'; X='\033[0m'
FAILS=0
ok(){ echo -e "${G}PASS${X}  $1"; }
bad(){ echo -e "${R}FAIL${X}  $1"; FAILS=$((FAILS+1)); }
eq(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }
has(){ case "$2" in *"$3"*) ok "$1";; *) bad "$1 (got '$2')";; esac; }
nonempty(){ if [ -n "$2" ]; then ok "$1"; else bad "$1"; fi; }
exists(){ local d=$1; shift; if k get "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
note(){ echo -e "      NOTE  $1"; }
skip(){ echo -e "\033[33mSKIP${X}  $1"; }

STATE=/tmp/cka-lab
TOKENS_FILE="$STATE/c7.tokens"
JOIN_FILE=/root/kubeadm-join.sh

echo "== c7: Prepare a node join =="

# ------------------------------------------------------- 1. the join file ---

FILE_CONTENT=""
if [ -r "$JOIN_FILE" ]; then
  ok "$JOIN_FILE exists and is readable"
  FILE_CONTENT=$(cat "$JOIN_FILE" 2>/dev/null)
else
  bad "$JOIN_FILE exists and is readable"
fi

nonempty "$JOIN_FILE is not empty" "$FILE_CONTENT"
has "$JOIN_FILE contains a 'kubeadm join' command" "$FILE_CONTENT" "kubeadm join"
has "$JOIN_FILE contains a --token argument" "$FILE_CONTENT" "--token"
has "$JOIN_FILE contains a --discovery-token-ca-cert-hash argument" "$FILE_CONTENT" "--discovery-token-ca-cert-hash"
has "$JOIN_FILE contains a CA certificate hash (sha256:...)" "$FILE_CONTENT" "sha256:"
has "$JOIN_FILE contains an https:// API server endpoint" "$FILE_CONTENT" "https://"

# ---------------------------------------------- 2. the token is real and new --

if ! command -v kubeadm >/dev/null 2>&1; then
  skip "the token in $JOIN_FILE is listed by 'kubeadm token list' - kubeadm is not installed on this machine"
  skip "kubeadm token list shows a token created for this exercise - kubeadm is not installed on this machine"
else
  TOKEN_LIST=$(kubeadm token list 2>/dev/null)
  IDS=$(printf '%s\n' "$TOKEN_LIST" | awk 'NF>0 {print $1}' | grep -E '^[a-z0-9]{6}$' | tr '\n' ' ')

  # The token in the file is <id>.<secret>; `kubeadm token list` shows the id.
  FILE_TOKEN=$(printf '%s' "$FILE_CONTENT" | grep -oE '[a-z0-9]{6}\.[a-z0-9]{16}' | head -1)
  if [ -n "$FILE_TOKEN" ]; then
    TOKEN_ID=$(printf '%s' "$FILE_TOKEN" | cut -d. -f1)
    has "the token in $JOIN_FILE is listed by 'kubeadm token list'" "$IDS" "$TOKEN_ID"
  else
    bad "the token in $JOIN_FILE is listed by 'kubeadm token list' (no token of the form abcdef.0123456789abcdef found in the file)"
  fi

  BEFORE=""
  if [ -f "$TOKENS_FILE" ]; then
    BEFORE=$(cat "$TOKENS_FILE" 2>/dev/null || true)
  fi
  NEW=""
  for t in $(printf '%s\n' "$TOKEN_LIST" | awk 'NF>0 {print $1}' | grep -E '^[a-z0-9]{6}$'); do
    if ! printf '%s\n' "$BEFORE" | grep -qx "$t"; then
      NEW="$NEW $t"
    fi
  done
  nonempty "kubeadm token list shows at least one token created for this exercise" "$NEW"
fi

note "The join command needs three things: the API server address and port,"
note "a token, and the CA certificate hash so the joining node trusts the"
note "API server. A token on its own is not enough."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c7 PASSED${X}"; else echo -e "${R}c7 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
