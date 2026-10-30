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

CTXFILE=/root/current-context.txt
HOSTFILE=/root/current-node.txt

echo "== c30: Know where you are before you act =="

# --- the live values ---
WANT_CTX="$(k config current-context 2>/dev/null || true)"
WANT_HOST="$(hostname 2>/dev/null || true)"
SHORT_HOST="$(hostname -s 2>/dev/null || true)"

nonempty "a kubectl context is set" "$WANT_CTX"
nonempty "the machine has a hostname" "$WANT_HOST"

# --- the context file ---
if [ -f "$CTXFILE" ]; then
  ok "$CTXFILE exists"
  RAW="$(cat "$CTXFILE" 2>/dev/null)"
  GOT="$(printf '%s' "$RAW" | sed -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//')"
  eq "the context name in $CTXFILE is correct" "$GOT" "$WANT_CTX"
  if printf '%s' "$RAW" | grep -qE '^[[:space:]]*[^[:space:]].*[[:space:]]*$'; then
    ok "$CTXFILE contains only the context name"
  else
    bad "$CTXFILE contains only the context name (got '$(printf '%s' "$RAW" | tr '\n' ' ')')"
  fi
else
  bad "$CTXFILE exists (file not found)"
fi

# --- the hostname file ---
if [ -f "$HOSTFILE" ]; then
  ok "$HOSTFILE exists"
  RAW="$(cat "$HOSTFILE" 2>/dev/null)"
  GOT="$(printf '%s' "$RAW" | sed -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//')"
  if [ "$GOT" = "$WANT_HOST" ] || [ -n "$SHORT_HOST" ] && [ "$GOT" = "$SHORT_HOST" ]; then
    ok "the hostname in $HOSTFILE is correct"
  else
    bad "the hostname in $HOSTFILE is correct (got '$GOT', want '$WANT_HOST')"
  fi
  if printf '%s' "$RAW" | grep -qE '^[[:space:]]*[^[:space:]].*[[:space:]]*$'; then
    ok "$HOSTFILE contains only the hostname"
  else
    bad "$HOSTFILE contains only the hostname (got '$(printf '%s' "$RAW" | tr '\n' ' ')')"
  fi
else
  bad "$HOSTFILE exists (file not found)"
fi

# --- the control plane version is reachable ---
if k version >/dev/null 2>&1; then
  ok "kubectl can reach the API server (kubectl version succeeds)"
else
  bad "kubectl can reach the API server (kubectl version failed)"
fi

note "This is the easiest question in the set and it is still worth doing. Each"
note "exam task can begin in a fresh session on a different node, and aliases and"
note "shell functions do not survive that. Two commands tell you whether you are"
note "pointed at the cluster you think you are."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c30 PASSED${X}"; else echo -e "${R}c30 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
