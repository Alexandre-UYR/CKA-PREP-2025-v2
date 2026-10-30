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

NS=sidecar
DEP=web

echo "== v1: A log nobody can read =="

if ! exists "Deployment $DEP exists in namespace $NS" -n "$NS" deploy "$DEP"; then
  echo; echo -e "${R}v1 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the containers ----
CN=$(k -n "$NS" get deploy "$DEP" \
     -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{"\n"}{end}' 2>/dev/null \
     | tr -d '\r' | grep -v '^[[:space:]]*$')
COUNT=$(printf '%s\n' "$CN" | grep -c '[^[:space:]]')
eq "the Deployment has exactly 2 containers" "$COUNT" "2"

if printf '%s\n' "$CN" | grep -qx 'logreader'; then
  ok "the Deployment has a container named logreader"
else
  bad "the Deployment has a container named logreader"
fi

SIDEIMG=$(k -n "$NS" get deploy "$DEP" \
          -o jsonpath='{.spec.template.spec.containers[?(@.name=="logreader")].image}' 2>/dev/null)
eq "the logreader sidecar uses busybox:1.36" "$SIDEIMG" "busybox:1.36"

SIDECMD=$(k -n "$NS" get deploy "$DEP" \
          -o jsonpath='{.spec.template.spec.containers[?(@.name=="logreader")].command}' 2>/dev/null)
nonempty "the logreader sidecar has a command" "$SIDECMD"
has "the logreader command reads /var/log/app.log" "$SIDECMD" "/var/log/app.log"
SIDELOW=$(printf '%s' "$SIDECMD" | tr '[:upper:]' '[:lower:]')
has "the logreader command tails the file" "$SIDELOW" "tail"

# ---- the app container, which must keep writing to the same path ----
APPC=$(printf '%s\n' "$CN" | grep -v '^logreader$' | grep -v '^[[:space:]]*$' | head -1)
if [ -n "$APPC" ]; then
  ok "the app container is '$APPC'"
  APPCMD=$(k -n "$NS" get deploy "$DEP" \
           -o jsonpath="{.spec.template.spec.containers[?(@.name==\"$APPC\")].command}" 2>/dev/null)
  has "the app container still writes to /var/log/app.log" "$APPCMD" "/var/log/app.log"
else
  bad "there is an app container next to the sidecar"
fi

# ---- the shared volume ----
VNAMES=$(k -n "$NS" get deploy "$DEP" \
         -o jsonpath='{range .spec.template.spec.volumes[*]}{.name}{"\n"}{end}' 2>/dev/null \
         | tr -d '\r' | grep -v '^[[:space:]]*$')
if printf '%s\n' "$VNAMES" | grep -qx 'shared-logs'; then
  ok "the Deployment has a volume named shared-logs"
else
  bad "the Deployment has a volume named shared-logs (got: $(printf '%s' "$VNAMES" | tr '\n' ' '))"
fi

VOBJ=$(k -n "$NS" get deploy "$DEP" \
       -o jsonpath='{.spec.template.spec.volumes[?(@.name=="shared-logs")]}' 2>/dev/null)
VED=$(k -n "$NS" get deploy "$DEP" \
      -o jsonpath='{.spec.template.spec.volumes[?(@.name=="shared-logs")].emptyDir}' 2>/dev/null)
IS_ED=0
case "$VOBJ" in *emptyDir*) IS_ED=1;; esac
[ -n "$VED" ] && IS_ED=1
if [ "$IS_ED" -eq 1 ]; then
  ok "the shared-logs volume is an emptyDir"
else
  bad "the shared-logs volume is an emptyDir (got '$VOBJ')"
fi

# ---- and both containers have to mount it at /var/log ----
for c in "$APPC" logreader; do
  [ -n "$c" ] || continue
  MP=$(k -n "$NS" get deploy "$DEP" \
       -o jsonpath="{.spec.template.spec.containers[?(@.name==\"$c\")].volumeMounts[?(@.name==\"shared-logs\")].mountPath}" 2>/dev/null)
  eq "container '$c' mounts shared-logs at /var/log" "$MP" "/var/log"
done

# ---- the workload ----
READYREP=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
eq "the Deployment has 1 ready replica" "$READYREP" "1"

# ---- and the log really is shared ----
echo "Reading /var/log/app.log from inside the sidecar..."
OUT=""
i=0
while [ "$i" -lt 30 ]; do
  OUT=$(k -n "$NS" exec deploy/"$DEP" -c logreader -- cat /var/log/app.log 2>/dev/null) || OUT=""
  [ -n "$OUT" ] && break
  sleep 2
  i=$((i+2))
done
nonempty "the sidecar can read the log through the shared volume" "$OUT"
has "what the sidecar reads is the app's own log" "$OUT" "app log line"

note "A file written into a container's writable layer is private to that container"
note "and is lost when it restarts. An emptyDir mounted at /var/log in both"
note "containers is what makes the log shared."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}v1 PASSED${X}"; else echo -e "${R}v1 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
