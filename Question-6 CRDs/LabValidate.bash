#!/bin/bash
# Grader for Question 6 (CRDs).
#
# The deliverables are two files under /root, so reading them may need sudo:
# try the plain path first and fall back to `sudo cat`.
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

# Read a file, falling back to sudo when /root is not readable by the current
# user. `sudo -n` keeps the grader from hanging on a password prompt.
readfile(){
  local p="$1"
  if [ -r "$p" ]; then cat -- "$p" 2>/dev/null; return 0; fi
  sudo -n cat -- "$p" 2>/dev/null
}
fileexists(){
  local p="$1"
  if [ -e "$p" ]; then return 0; fi
  sudo -n ls -d "$p" >/dev/null 2>&1
}

# The cert-manager CRDs that LabSetUp.bash installs.
CRDS="certificaterequests.cert-manager.io \
certificates.cert-manager.io \
challenges.acme.cert-manager.io \
clusterissuers.cert-manager.io \
issuers.cert-manager.io \
orders.acme.cert-manager.io"

# 1. A list of all cert-manager CRDs, saved to /root/resources.yaml
if fileexists /root/resources.yaml; then
  ok "/root/resources.yaml exists"
else
  bad "/root/resources.yaml exists (file not found)"
fi
RES="$(readfile /root/resources.yaml)"
nonempty "/root/resources.yaml is not empty" "$RES"
for c in $CRDS; do
  has "/root/resources.yaml lists the CRD $c" "$RES" "$c"
done

# 2. The documentation for the subject field of the Certificate custom
#    resource, saved to /root/subject.yaml
if fileexists /root/subject.yaml; then
  ok "/root/subject.yaml exists"
else
  bad "/root/subject.yaml exists (file not found)"
fi
SUB="$(readfile /root/subject.yaml)"
nonempty "/root/subject.yaml is not empty" "$SUB"
has "/root/subject.yaml documents the subject field" "$SUB" "subject"

if [ "$FAILS" -eq 0 ]; then echo -e "${G}Q6 PASSED${X}"; else echo -e "${R}Q6 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
