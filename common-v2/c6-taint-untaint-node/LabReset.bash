#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }

STATE=/tmp/cka-lab
NS=taints
NODES_FILE="$STATE/c6.nodes"
UID_FILE="$STATE/c6.uid"

# ------------------------------------------- 1. the do-not-use taint is gone --

# `kubectl taint` has no --ignore-not-found: removing a taint that is not
# there is an error, which is harmless here.
for n in $(k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
  k taint nodes "$n" do-not-use=true:NoSchedule- >/dev/null 2>&1 || true
done

# --------------------------------- 2. the dedicated=payments taint is back --

PAYMENTS=""
if [ -f "$NODES_FILE" ]; then
  PAYMENTS=$(awk '$1=="payments"{print $2}' "$NODES_FILE")
fi

if [ -n "$PAYMENTS" ] && k get node "$PAYMENTS" >/dev/null 2>&1; then
  k taint nodes "$PAYMENTS" dedicated=payments:NoSchedule >/dev/null 2>&1 || true
fi

# ------------------------------------------------------- 3. the namespace ----

k delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null

# ------------------------------------------------------ 4. the state files ---

rm -f "$NODES_FILE" 2>/dev/null || true
rm -f "$UID_FILE" 2>/dev/null || true

echo "c6 reset: do-not-use taint removed, dedicated=payments restored on ${PAYMENTS:-unknown}, namespace $NS deleted"
