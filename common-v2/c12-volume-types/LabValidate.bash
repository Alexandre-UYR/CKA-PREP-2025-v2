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

NS=volumes
POD=all-volumes

echo "== c12: The four everyday volume types =="

if ! exists "Pod $POD exists in namespace $NS" -n "$NS" pod "$POD"; then
  echo; echo -e "${R}c12 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the Pod has to run ----
eq "the Pod is Running" \
  "$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null)" "Running"

# ---- exactly four volumes, one of each kind ----
ALLVOLS=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.volumes[*].name}' 2>/dev/null)
NVOLS=$(printf '%s' "$ALLVOLS" | wc -w | tr -d ' ')
eq "the Pod template has exactly 4 volumes" "$NVOLS" "4"

PODJSON=$(k -n "$NS" get pod "$POD" -o json 2>/dev/null)
# Counts the volume sources by key. A volume source key only ever appears in
# spec.volumes, so these counts are the number of volumes of each kind.
cntkey(){ printf '%s' "$PODJSON" | grep -o "\"$1\":" | wc -l | tr -d ' '; return 0; }

eq "exactly one volume is an emptyDir" "$(cntkey emptyDir)" "1"
eq "exactly one volume is a ConfigMap volume" "$(cntkey configMap)" "1"
eq "exactly one volume is a Secret volume" "$(cntkey secret)" "1"
eq "exactly one volume is a hostPath volume" "$(cntkey hostPath)" "1"

# ---- and each one points at the right source ----
CFGVOL=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.volumes[?(@.configMap.name=="app-config")].name}' 2>/dev/null)
SECVOL=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.volumes[?(@.secret.secretName=="app-secret")].name}' 2>/dev/null)
HOSTVOL=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.volumes[?(@.hostPath.path=="/tmp/hostdata")].name}' 2>/dev/null)

nonempty "a volume uses the ConfigMap app-config" "$CFGVOL"
nonempty "a volume uses the Secret app-secret" "$SECVOL"
nonempty "a volume is a hostPath at /tmp/hostdata" "$HOSTVOL"

# The emptyDir volume is the one that is not any of the three above.
KNOWN=" $CFGVOL $SECVOL $HOSTVOL "
EMPTYVOL=""
for v in $ALLVOLS; do
  case "$KNOWN" in
    *" $v "*) ;;
    *) EMPTYVOL="$v" ;;
  esac
done
nonempty "a volume is an emptyDir" "$EMPTYVOL"

# ---- one mount each, at the right path ----
mp(){ k -n "$NS" get pod "$POD" -o jsonpath="{.spec.containers[*].volumeMounts[?(@.name==\"$1\")].mountPath}" 2>/dev/null; }

if [ -n "$EMPTYVOL" ]; then
  eq "the emptyDir volume is mounted at /tmp" "$(mp "$EMPTYVOL")" "/tmp"
else
  skip "the /tmp mount check (no emptyDir volume was found)"
fi
if [ -n "$CFGVOL" ]; then
  eq "the ConfigMap volume is mounted at /etc/config" "$(mp "$CFGVOL")" "/etc/config"
else
  skip "the /etc/config mount check (no volume uses the ConfigMap app-config)"
fi
if [ -n "$SECVOL" ]; then
  eq "the Secret volume is mounted at /etc/secret" "$(mp "$SECVOL")" "/etc/secret"
else
  skip "the /etc/secret mount check (no volume uses the Secret app-secret)"
fi
if [ -n "$HOSTVOL" ]; then
  eq "the hostPath volume is mounted at /host" "$(mp "$HOSTVOL")" "/host"
else
  skip "the /host mount check (no volume is a hostPath at /tmp/hostdata)"
fi

# ---- live check: the mounts really are there ----
i=0
while [ $i -lt 15 ]; do
  PHASE=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null)
  [ "$PHASE" = "Running" ] && break
  i=$((i+1)); sleep 2
done

# `kubectl exec` needs a container name as soon as the Pod has more than one,
# so fall back to the first container when the plain form is refused.
CTN=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[0].name}' 2>/dev/null)
in_pod(){ k -n "$NS" exec "$POD" -- "$@" 2>/dev/null || k -n "$NS" exec "$POD" -c "$CTN" -- "$@" 2>/dev/null; }

LS_CFG=$(in_pod ls /etc/config | tr -d '\r')
has "the ConfigMap mount shows nginx.conf inside the Pod" "$LS_CFG" "nginx.conf"

LS_SEC=$(in_pod ls /etc/secret | tr -d '\r')
nonempty "the Secret mount is not empty inside the Pod" "$(printf '%s' "$LS_SEC" | tr -d '[:space:]')"

if in_pod ls /tmp >/dev/null 2>&1; then
  ok "the emptyDir mount at /tmp can be listed inside the Pod"
else
  bad "the emptyDir mount at /tmp can be listed inside the Pod (kubectl -n $NS exec $POD -- ls /tmp failed)"
fi

note "A ConfigMap mounted as a volume appears as files, one per key, and is"
note "read-only. A Secret mounted as a volume appears the same way, but the"
note "kubelet decodes the base64 for you."
note "An emptyDir lives and dies with the Pod. A hostPath is the node's own"
note "filesystem - it is there whether or not a Pod is using it, and it only"
note "exists on the node the Pod actually landed on."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c12 PASSED${X}"; else echo -e "${R}c12 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
