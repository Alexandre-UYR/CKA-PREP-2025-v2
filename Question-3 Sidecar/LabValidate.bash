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

NS=default
UID_FILE=/tmp/cka-lab/q3.deploy.uid

echo "== Q3: sidecar container =="

# --- The deployment that had to be updated, not re-created ---------------
exists "Deployment wordpress exists in namespace $NS" deploy wordpress -n "$NS"

if [ -f "$UID_FILE" ]; then
  SETUP_UID="$(cat "$UID_FILE" 2>/dev/null)"
  NOW_UID="$(k get deploy wordpress -n "$NS" -o jsonpath='{.metadata.uid}' 2>/dev/null)"
  eq "Deployment wordpress is the SAME deployment created during setup (it was updated, not deleted and re-created)" "$NOW_UID" "$SETUP_UID"
else
  bad "Deployment wordpress is the SAME deployment created during setup (uid file $UID_FILE is missing - re-run the setup)"
fi

# --- The pod template ----------------------------------------------------
NAMES="$(k get deploy wordpress -n "$NS" -o jsonpath='{.spec.template.spec.containers[*].name}' 2>/dev/null)"
COUNT="$(printf '%s\n' "$NAMES" | wc -w | tr -d ' ')"
eq "The pod template has exactly 2 containers (wordpress + sidecar)" "${COUNT:-0}" "2"

SIDECAR_IMG="$(k get deploy wordpress -n "$NS" -o jsonpath='{.spec.template.spec.containers[?(@.name=="sidecar")].image}' 2>/dev/null)"
eq "Container sidecar uses image busybox:stable" "$SIDECAR_IMG" "busybox:stable"

SIDECAR_CMD="$(k get deploy wordpress -n "$NS" -o jsonpath='{.spec.template.spec.containers[?(@.name=="sidecar")].command}' 2>/dev/null)"
SIDECAR_ARGS="$(k get deploy wordpress -n "$NS" -o jsonpath='{.spec.template.spec.containers[?(@.name=="sidecar")].args}' 2>/dev/null)"
has "Container sidecar runs 'tail -f /var/log/wordpress.log'" "$SIDECAR_CMD $SIDECAR_ARGS" "tail -f /var/log/wordpress.log"

# --- The shared volume ---------------------------------------------------
WP_MOUNT="$(k get deploy wordpress -n "$NS" -o jsonpath='{.spec.template.spec.containers[?(@.name=="wordpress")].volumeMounts[?(@.mountPath=="/var/log")].name}' 2>/dev/null)"
nonempty "Container wordpress mounts a volume at /var/log" "$WP_MOUNT"
SC_MOUNT="$(k get deploy wordpress -n "$NS" -o jsonpath='{.spec.template.spec.containers[?(@.name=="sidecar")].volumeMounts[?(@.mountPath=="/var/log")].name}' 2>/dev/null)"
nonempty "Container sidecar mounts a volume at /var/log" "$SC_MOUNT"

if [ -n "$WP_MOUNT" ] && [ -n "$SC_MOUNT" ]; then
  eq "Both containers mount the SAME volume (that is what makes the log file shared)" "$SC_MOUNT" "$WP_MOUNT"
else
  bad "Both containers mount the SAME volume (that is what makes the log file shared) (wordpress='$WP_MOUNT', sidecar='$SC_MOUNT')"
fi

# --- The workload still has to be healthy --------------------------------
READY="$(k get deploy wordpress -n "$NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"
eq "Deployment wordpress has 1 ready replica" "$READY" "1"

if k -n "$NS" exec deploy/wordpress -c sidecar -- ls -l /var/log/wordpress.log >/dev/null 2>&1; then
  ok "The shared volume works: /var/log/wordpress.log is visible inside the sidecar container"
else
  bad "The shared volume works: /var/log/wordpress.log is visible inside the sidecar container (ls -l /var/log/wordpress.log failed inside the sidecar)"
fi

if [ "$FAILS" -eq 0 ]; then echo -e "${G}Q3 PASSED${X}"; else echo -e "${R}Q3 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
