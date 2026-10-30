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

FILE=/root/ready-nodes.txt

echo "== c29: Count the ready nodes =="

# --- work out the expected answer from the cluster as it is right now ---
# The control-plane node is the one carrying the control-plane taint.
CP=$(k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.taints}{"\n"}{end}' 2>/dev/null \
     | grep 'key:node-role.kubernetes.io/control-plane' | awk '{print $1}' | head -1)

# node|ReadyStatus for every node
READYMAP=$(k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null)

WANT=$(printf '%s\n' "$READYMAP" | awk -F'|' -v cp="$CP" '$2=="True" && $1!=cp' | wc -l | tr -d ' ')
ALLN=$(printf '%s\n' "$READYMAP" | grep -c '|' || true)

if [ -z "${ALLN:-}" ] || [ "${ALLN:-0}" -eq 0 ] 2>/dev/null; then
  bad "the node list could not be read from the cluster"
else
  note "the cluster has ${ALLN} node(s); the control-plane node is '${CP:-<none>}'"
  note "Ready and not the control plane: ${WANT}"
fi

# --- the candidate's answer ---
if [ ! -f "$FILE" ]; then
  bad "$FILE exists (file not found)"
else
  ok "$FILE exists"
  RAW=$(cat "$FILE" 2>/dev/null)
  GOT=$(printf '%s' "$RAW" | tr -d '[:space:]')

  if printf '%s' "$RAW" | grep -qE '^[[:space:]]*[0-9]+[[:space:]]*$'; then
    ok "$FILE contains nothing but a number"
  else
    bad "$FILE contains nothing but a number (got '$(printf '%s' "$RAW" | tr '\n' ' ')')"
  fi

  if [ -z "$GOT" ]; then
    bad "$FILE holds the count (the file is empty)"
  elif ! printf '%s' "$GOT" | grep -qE '^[0-9]+$'; then
    bad "$FILE holds a number (got '$GOT')"
  else
    eq "the count in $FILE is correct" "$GOT" "${WANT:-0}"
  fi
fi

note "Ready and schedulable are different things: a node can be Ready and still"
note "be tainted so that ordinary pods never land on it, and a node that is"
note "Unknown (heartbeat lost) is not Ready either."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c29 PASSED${X}"; else echo -e "${R}c29 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
