#!/bin/bash
set -uo pipefail

G='\033[32m'; R='\033[31m'; X='\033[0m'
FAILS=0
ok(){ echo -e "${G}PASS${X}  $1"; }
bad(){ echo -e "${R}FAIL${X}  $1"; FAILS=$((FAILS+1)); }
eq(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }
has(){ case "$2" in *"$3"*) ok "$1";; *) bad "$1 (got '$2')";; esac; }
nonempty(){ if [ -n "$2" ]; then ok "$1"; else bad "$1"; fi; }
note(){ echo -e "      NOTE  $1"; }

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

echo "== Q9 cri-dockerd =="

# ---- the package is installed ----
STATUS=$(dpkg-query -W -f='${Status}' cri-dockerd 2>/dev/null || true)
eq "the cri-dockerd package is installed" "$STATUS" "install ok installed"

# ---- the service is enabled and running ----
ENABLED=$(systemctl is-enabled cri-docker.service 2>/dev/null || true)
eq "cri-docker.service is enabled" "$ENABLED" "enabled"

ACTIVE=$(systemctl is-active cri-docker.service 2>/dev/null || true)
eq "cri-docker.service is running" "$ACTIVE" "active"

# ---- the four sysctls have the required live values ----
check_sysctl(){
  local key="$1" want="$2" got
  got=$(sysctl -n "$key" 2>/dev/null | tr -d '[:space:]')
  if [ -z "$got" ]; then
    bad "$key is set to $want (this kernel does not expose '$key')"
  else
    eq "$key is set to $want" "$got" "$want"
  fi
}

check_sysctl net.bridge.bridge-nf-call-iptables 1
check_sysctl net.ipv6.conf.all.forwarding 1
check_sysctl net.ipv4.ip_forward 1
check_sysctl net.netfilter.nf_conntrack_max 131072

# ---- and they survive a reboot ----
CONF=/etc/sysctl.d/kube.conf
CONF_CONTENT=$($SUDO cat "$CONF" 2>/dev/null || cat "$CONF" 2>/dev/null || true)
if [ -z "$CONF_CONTENT" ]; then
  bad "$CONF exists and holds the four settings (not found)"
else
  ok "$CONF exists"
  has "$CONF sets net.bridge.bridge-nf-call-iptables=1" "$CONF_CONTENT" "net.bridge.bridge-nf-call-iptables=1"
  has "$CONF sets net.ipv6.conf.all.forwarding=1" "$CONF_CONTENT" "net.ipv6.conf.all.forwarding=1"
  has "$CONF sets net.ipv4.ip_forward=1" "$CONF_CONTENT" "net.ipv4.ip_forward=1"
  has "$CONF sets net.netfilter.nf_conntrack_max=131072" "$CONF_CONTENT" "net.netfilter.nf_conntrack_max=131072"
fi

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}Q9 PASSED${X}"; else echo -e "${R}Q9 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
