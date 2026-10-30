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

LABDIR=/tmp/cka-lab
LOGSTATE="$LABDIR/x3.logs"
COMPONENTS="apiserver scheduler controller-manager kubelet kube-proxy"

echo "== x3: Which log belongs to which component =="

# ---- helpers ----------------------------------------------------------------

# The task names /root/<name>; fall back to $HOME/<name> when the lab is run
# as a user who cannot write /root.
target_file(){
  local name=$1
  if [ -f "/root/$name" ]; then printf '%s\n' "/root/$name"
  elif [ -f "$HOME/$name" ]; then printf '%s\n' "$HOME/$name"
  else printf '%s\n' "/root/$name"; fi
}

# The log files live in root-owned directories.
path_exists(){
  local p=$1
  [ -n "$p" ] || return 1
  if [ -e "$p" ]; then return 0; fi
  if command -v sudo >/dev/null 2>&1; then
    sudo -n test -e "$p" >/dev/null 2>&1 && return 0
  fi
  return 1
}

read_file(){
  local f=$1
  if [ -r "$f" ]; then
    cat "$f" 2>/dev/null
  elif command -v sudo >/dev/null 2>&1; then
    sudo -n cat "$f" 2>/dev/null || cat "$f" 2>/dev/null
  else
    cat "$f" 2>/dev/null
  fi
}

# Does this path name the given component's log? The kubeadm names carry a
# kube- prefix, and the real file under /var/log/containers lives in a
# directory named after the container, so the name is looked for in the file's
# name and in the path around it.
matches_component(){
  local p=$1 comp=$2
  local base
  base=$(basename "$p" 2>/dev/null | tr 'A-Z' 'a-z')
  case "$comp" in
    apiserver)
      case "$base" in *apiserver*|*api-server*) return 0;; esac
      case "$p" in *apiserver*|*api-server*) return 0;; esac ;;
    scheduler)
      case "$base" in *scheduler*) return 0;; esac
      case "$p" in *scheduler*) return 0;; esac ;;
    controller-manager)
      case "$base" in *controller-manager*|*controller_manager*|*controllermanager*) return 0;; esac
      case "$p" in *controller-manager*|*controller_manager*|*controllermanager*) return 0;; esac ;;
    kubelet)
      case "$base" in *kubelet*) return 0;; esac
      case "$p" in *kubelet*) return 0;; esac ;;
    kube-proxy)
      case "$base" in *kube-proxy*|*kubeproxy*|*proxy*) return 0;; esac
      case "$p" in *kube-proxy*|*kubeproxy*|*proxy*) return 0;; esac ;;
  esac
  return 1
}

# What the setup found for this component, if anything.
recorded_path(){
  sed -n "s/^$1=//p" "$LOGSTATE" 2>/dev/null | head -n 1
}

# ---- the answers ------------------------------------------------------------

LOGFILE=$(target_file control-plane-logs.txt)
COMPFILE=$(target_file scheduler-component.txt)

if [ -f "$LOGFILE" ]; then
  ok "the log file list $LOGFILE exists"
else
  bad "the log file list $LOGFILE exists"
fi

# The usable lines: not empty, not a comment.
LINES=""
if [ -f "$LOGFILE" ]; then
  LINES=$(read_file "$LOGFILE" | tr -d '\r' | sed -e 's/[[:space:]]*$//' | grep -v '^$' | grep -v '^#')
fi

COUNT=$(printf '%s\n' "$LINES" | grep -c . | tr -d ' ')
if [ "$COUNT" -ge 5 ] 2>/dev/null; then
  ok "the log file list has five paths in it (it has $COUNT lines)"
else
  bad "the log file list has five paths in it (it has ${COUNT:-0} lines)"
fi
if [ "${COUNT:-0}" -gt 5 ] 2>/dev/null; then
  note "The list has more than five lines; only the first five are graded."
fi

# ---- each line, in order ----------------------------------------------------

i=0
for comp in $COMPONENTS; do
  i=$((i+1))
  LINE=$(printf '%s\n' "$LINES" | sed -n "${i}p")
  LINE=$(printf '%s' "$LINE" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

  if [ -z "$LINE" ]; then
    bad "line $i is the $comp's log file"
    continue
  fi

  REC=$(recorded_path "$comp")
  if [ -z "$REC" ]; then
    skip "line $i is the $comp's log file (this node has no log for the $comp)"
    continue
  fi

  if matches_component "$LINE" "$comp"; then
    ok "line $i names the $comp's log ($LINE)"
  else
    bad "line $i names the $comp's log (got '$LINE')"
  fi

  if path_exists "$LINE"; then
    ok "line $i is a path that exists on this node ($LINE)"
  else
    bad "line $i is a path that exists on this node (got '$LINE')"
  fi
done

# ---- the second question ----------------------------------------------------

if [ -f "$COMPFILE" ]; then
  ok "the answer file $COMPFILE exists"
  COMP=$(read_file "$COMPFILE" | tr -d '\r\n' | tr 'A-Z' 'a-z' | sed -e 's/[[:space:]]*$//')
  case "$COMP" in
    *scheduler*) ok "the component that makes scheduling decisions is the scheduler (it said '$COMP')";;
    *) bad "the component that makes scheduling decisions is the scheduler (it said '${COMP:-<nothing>}')";;
  esac
else
  bad "the answer file $COMPFILE exists"
fi

note "The control plane's own components run as static pods: their output is in"
note "/var/log/containers/, and the kubelet makes a symlink under /var/log named"
note "after each of them. The kubelet's own log is a plain file under /var/log."
note "The API server serves the API, the scheduler decides WHERE a pod runs,"
note "the controller manager reconciles the state you asked for, and kube-proxy"
note "programs the node's network rules."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}x3 PASSED${X}"; else echo -e "${R}x3 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
