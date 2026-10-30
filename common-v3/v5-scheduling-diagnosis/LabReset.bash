#!/bin/bash
set -uo pipefail

k(){ kubectl "$@"; }
STATE_FILE="${TMPDIR:-/tmp}/cka-v5-scheduling-diagnosis.env"

# The namespace holds the Pod and nothing else.
k delete namespace sched --ignore-not-found --timeout=120s >/dev/null

# The nodes are cluster state, not namespace state: deleting the namespace
# does not un-cordon a node, remove a taint, or remove a label. All three
# have to be undone explicitly, and they have to be undone on EVERY node -
# the candidate was free to fix the problem on whichever node it chose.
for n in $(k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
  [ -n "$n" ] || continue
  k uncordon "$n" >/dev/null 2>&1 || true
  k taint node "$n" dedicated=db- >/dev/null 2>&1 || true
  k taint node "$n" dedicated- >/dev/null 2>&1 || true
  k label node "$n" disk- >/dev/null 2>&1 || true
done

rm -f "$STATE_FILE"

echo "v5 reset: namespace sched removed, every node uncordoned, the dedicated=db taint and the disk labels cleared"
