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

NS=shared
POD=writer

echo "== w20: One volume, two containers =="

# ---- the Pod ----
if k -n "$NS" get pod "$POD" >/dev/null 2>&1; then
  ok "Pod $POD exists in namespace $NS"
else
  bad "Pod $POD exists in namespace $NS (not found)"
fi

# ---- exactly two containers ----
COUNT=$(k -n "$NS" get pod "$POD" -o go-template='{{len .spec.containers}}' 2>/dev/null)
eq "the Pod has exactly 2 containers" "$COUNT" "2"

# ---- both mount the same volume, at /data ----
VOL0=$(k -n "$NS" get pod "$POD" -o jsonpath='{range .spec.containers[0].volumeMounts[?(@.mountPath=="/data")]}{.name}{end}' 2>/dev/null)
VOL1=$(k -n "$NS" get pod "$POD" -o jsonpath='{range .spec.containers[1].volumeMounts[?(@.mountPath=="/data")]}{.name}{end}' 2>/dev/null)

nonempty "the first container mounts a volume at /data" "$VOL0"
nonempty "the second container mounts a volume at /data" "$VOL1"
eq "both containers mount the SAME volume name" "$VOL0" "$VOL1"

# ---- and that volume is an emptyDir ----
VOLNAME=$(printf '%s' "$VOL0" | tr -d ' ')
VOLTYPE=$(k -n "$NS" get pod "$POD" -o go-template="{{range .spec.volumes}}{{if eq .name \"$VOLNAME\"}}emptyDir{{end}}{{end}}" 2>/dev/null)
eq "the shared volume '$VOLNAME' is an emptyDir" "$VOLTYPE" "emptyDir"

# ---- the Pod is running and both containers are ready ----
PHASE=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null)
eq "the Pod is Running" "$PHASE" "Running"

READYCOUNT=$(k -n "$NS" get pod "$POD" -o go-template='{{range .status.containerStatuses}}{{if .ready}}R{{end}}{{end}}' 2>/dev/null)
eq "both containers are Ready" "$READYCOUNT" "RR"

# ---- live check: read the file from the SECOND container ----
C1=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[1].name}' 2>/dev/null)
C0=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[0].name}' 2>/dev/null)

if [ -z "$C1" ]; then
  bad "the second container can be exec'd into (no second container found)"
else
  HI=$(k -n "$NS" exec "$POD" -c "$C1" -- cat /data/hi 2>/dev/null | tr -d '\r\n')
  eq "the second container ($C1) reads 'hello' from /data/hi" "$HI" "hello"

  # And prove the two containers really share one directory: write a marker in
  # the first container, read it back in the second.
  k -n "$NS" exec "$POD" -c "$C0" -- sh -c 'echo shared-proof > /data/.cka-shared-check' >/dev/null 2>&1
  MARK=$(k -n "$NS" exec "$POD" -c "$C1" -- cat /data/.cka-shared-check 2>/dev/null | tr -d '\r\n')
  eq "a file written in the first container ($C0) is visible in the second" "$MARK" "shared-proof"
  k -n "$NS" exec "$POD" -c "$C1" -- rm -f /data/.cka-shared-check >/dev/null 2>&1
fi

# Informational only: which container is the one doing the writing.
WRITEVOL=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[0].command}' 2>/dev/null)
case "$WRITEVOL" in
  */data/hi*|*"/data/hi"*) : ;;
  *) note "the first container's command does not mention /data/hi - check that the container that writes the file is still one of the two" ;;
esac

note "An emptyDir belongs to the Pod, not to a container: every container in"
note "the Pod sees the same directory. Another Pod with a volume of the same"
note "name gets a DIFFERENT directory - that is what a PersistentVolume is for."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}w20 PASSED${X}"; else echo -e "${R}w20 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
