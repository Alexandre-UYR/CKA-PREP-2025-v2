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
skip(){ echo -e "      SKIP  $1"; }

NS=metrics
NODEFILE=/root/busiest-node.txt
PODFILE=/root/hottest-pod.txt

# A memory value such as 1920Mi, 512Ki or 3Gi, in MiB.
mem_to_mib(){
  local v="$1" num unit
  num="${v%%[A-Za-z]*}"
  unit="${v#$num}"
  case "$unit" in
    Ki) awk -v n="$num" 'BEGIN{printf "%.3f", n/1024}';;
    Mi) awk -v n="$num" 'BEGIN{printf "%.3f", n}';;
    Gi) awk -v n="$num" 'BEGIN{printf "%.3f", n*1024}';;
    Ti) awk -v n="$num" 'BEGIN{printf "%.3f", n*1048576}';;
    *)  awk -v n="$num" 'BEGIN{printf "%.3f", n/1048576}';;
  esac
}

# The name and the memory of the heaviest thing in a `kubectl top` table.
# The memory column is the one with a unit on it; the CPU columns never have
# one, so they are skipped.
top_table(){
  k top "$@" --no-headers 2>/dev/null \
    | awk '{m=""; for(i=2;i<=NF;i++) if ($i ~ /^[0-9.]+(Ki|Mi|Gi|Ti)$/) {m=$i; break}; if(m!="") print $1, m}'
}

echo "== x13: Which machine is the busiest =="

# ---------------------------------------------------------------------------
# The metrics server
# ---------------------------------------------------------------------------
MDEPLOY=$(k -n kube-system get deployment -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
          | grep -i 'metrics' | head -n 1)
if [ -n "$MDEPLOY" ]; then
  ok "a metrics server Deployment exists in kube-system ($MDEPLOY)"
  READY=$(k -n kube-system get deployment "$MDEPLOY" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  if [ "${READY:-0}" -ge 1 ]; then
    ok "the metrics server has a ready replica"
  else
    note "the metrics server has no ready replica yet - 'kubectl top' may not answer"
  fi
else
  bad "a metrics server Deployment exists in kube-system (found none)"
fi

# ---------------------------------------------------------------------------
# Does kubectl top work?
# ---------------------------------------------------------------------------
TOPOUT=$(k top nodes 2>/dev/null)
TOPRC=$?
if [ "$TOPRC" -eq 0 ] && [ -n "$TOPOUT" ]; then
  TOPNODES=1
  ok "kubectl top nodes works"
else
  TOPNODES=0
  skip "kubectl top nodes does not work, so the comparison checks are skipped"
  note "the reason: $(k top nodes 2>&1 >/dev/null | head -n 2 | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
# The busiest node
# ---------------------------------------------------------------------------
if [ -f "$NODEFILE" ]; then
  ok "the file $NODEFILE exists"
  GOTNODE=$(head -n 1 "$NODEFILE" 2>/dev/null | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  nonempty "$NODEFILE holds a node name" "$GOTNODE"
else
  bad "the file $NODEFILE exists"
  GOTNODE=""
fi

if [ "$TOPNODES" -eq 1 ]; then
  BEST=$(top_table nodes | while read -r n m; do echo "$(mem_to_mib "$m") $n"; done \
         | sort -k1 -n | tail -n 1 | awk '{print $2}')
  if [ -z "$BEST" ]; then
    bad "the busiest node could be read from 'kubectl top nodes' (the output could not be parsed)"
  else
    eq "$NODEFILE holds the node with the highest memory usage" "$GOTNODE" "$BEST"
  fi
else
  skip "the comparison between $NODEFILE and 'kubectl top nodes'"
fi

# ---------------------------------------------------------------------------
# The hungriest pod in the namespace
# ---------------------------------------------------------------------------
if [ -f "$PODFILE" ]; then
  ok "the file $PODFILE exists"
  GOTPOD=$(head -n 1 "$PODFILE" 2>/dev/null | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  nonempty "$PODFILE holds namespace/podname" "$GOTPOD"
  case "$GOTPOD" in
    "$NS"/*) ok "$PODFILE holds the pod in the form namespace/podname";;
    *) bad "$PODFILE holds the pod in the form namespace/podname (got '$GOTPOD')";;
  esac
else
  bad "the file $PODFILE exists"
  GOTPOD=""
fi

PODOUT=$(k top pods -n "$NS" 2>/dev/null)
PODRC=$?
if [ "$PODRC" -eq 0 ] && [ -n "$PODOUT" ]; then
  HOTPOD=$(top_table pods -n "$NS" | while read -r p m; do echo "$(mem_to_mib "$m") $p"; done \
           | sort -k1 -n | tail -n 1 | awk '{print $2}')
  if [ -z "$HOTPOD" ]; then
    bad "the pod with the highest memory usage could be read from 'kubectl top pods -n $NS' (the output could not be parsed)"
  else
    eq "$PODFILE holds the pod with the highest memory usage" "$GOTPOD" "$NS/$HOTPOD"
  fi
else
  skip "kubectl top pods -n $NS does not work, so the comparison check is skipped"
  note "the reason: $(k top pods -n "$NS" 2>&1 >/dev/null | head -n 2 | tr '\n' ' ')"
fi

note "The metrics API is not part of Kubernetes: it is an API server"
note "extension, so 'kubectl top' needs something like metrics-server"
note "installed and reachable before it can answer anything."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}x13 PASSED${X}"; else echo -e "${R}x13 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
