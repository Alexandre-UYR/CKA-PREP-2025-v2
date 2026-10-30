#!/bin/bash
set -e

# x3 - Which log belongs to which component
#
# This is a NODE-level question: it is run on the control-plane node of a
# kubeadm cluster. The setup does not create anything - the pre-state is the
# node's own log files. It records which of the five components really has a
# log on this machine, so the grader knows what it can check, and prints them.
#
# Nothing here needs kubectl: the answer is a file on this machine.

LABDIR=/tmp/cka-lab
LOGSTATE="$LABDIR/x3.logs"
COMPONENTS="apiserver scheduler controller-manager kubelet kube-proxy"

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

mkdir -p "$LABDIR"

# ---- find the log of one component ------------------------------------------
# The plain names from the question first, then the kubeadm names (which carry
# a kube- prefix), then the container logs themselves.

find_log(){
  local comp=$1 c
  case "$comp" in
    apiserver)
      set -- /var/log/kube-apiserver.log /var/log/apiserver.log \
             /var/log/containers/kube-apiserver-*.log ;;
    scheduler)
      set -- /var/log/kube-scheduler.log /var/log/scheduler.log \
             /var/log/containers/kube-scheduler-*.log ;;
    controller-manager)
      set -- /var/log/kube-controller-manager.log /var/log/controller-manager.log \
             /var/log/containers/kube-controller-manager-*.log ;;
    kubelet)
      set -- /var/log/kubelet.log /var/log/containers/kubelet-*.log ;;
    kube-proxy)
      set -- /var/log/kube-proxy.log /var/log/proxy.log \
             /var/log/containers/kube-proxy-*.log ;;
    *)
      set -- ;;
  esac
  for c in $@; do
    if [ -e "$c" ]; then printf '%s\n' "$c"; return 0; fi
  done
  return 1
}

# ---- record and print -------------------------------------------------------

: > "$LOGSTATE"

echo "x3 environment ready"
echo "   - this is a NODE-level question: run it on the control-plane node"

if [ -d /etc/kubernetes/manifests ]; then
  echo "   - static pod manifests: /etc/kubernetes/manifests"
else
  echo "   - ⚠️  no /etc/kubernetes/manifests here - is this the control-plane node?"
fi

echo "   - the log files this node has:"
FOUND=0
for comp in $COMPONENTS; do
  P=$(find_log "$comp" || true)
  if [ -n "$P" ]; then
    printf '%s=%s\n' "$comp" "$P" >> "$LOGSTATE"
    printf '       %-20s %s\n' "$comp" "$P"
    FOUND=$((FOUND+1))
  else
    printf '       %-20s %s\n' "$comp" "<not found on this node>"
  fi
done

echo "   - recorded in: $LOGSTATE"
echo "   - Task: write the five paths to /root/control-plane-logs.txt, one per"
echo "     line, in the order API server, scheduler, controller manager, kubelet,"
echo "     kube-proxy - and name the component that makes scheduling decisions"
echo "     in /root/scheduler-component.txt"

if [ "$FOUND" -lt 5 ]; then
  echo
  echo "⚠️  Only $FOUND of the 5 component logs were found on this node." >&2
  echo "    The lines for the components that are missing are skipped by the" >&2
  echo "    grader rather than failed. Check that the static pods and" >&2
  echo "    kube-proxy are running on this node." >&2
fi
