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

NS=init
DEP=cfg

echo "== v2: The app that cannot start =="

if ! exists "Deployment $DEP exists in namespace $NS" -n "$NS" deploy "$DEP"; then
  echo; echo -e "${R}v2 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the volumes ----
VOLNAMES=$(k -n "$NS" get deploy "$DEP" \
           -o jsonpath='{range .spec.template.spec.volumes[*]}{.name}{"\n"}{end}' 2>/dev/null \
           | tr -d '\r' | grep -v '^[[:space:]]*$')

EDVOL=""
CMVOL=""
for v in $VOLNAMES; do
  VOBJ=$(k -n "$NS" get deploy "$DEP" \
         -o jsonpath="{.spec.template.spec.volumes[?(@.name==\"$v\")]}" 2>/dev/null)
  ED=$(k -n "$NS" get deploy "$DEP" \
       -o jsonpath="{.spec.template.spec.volumes[?(@.name==\"$v\")].emptyDir}" 2>/dev/null)
  case "$VOBJ" in
    *emptyDir*) [ -z "$EDVOL" ] && EDVOL="$v";;
  esac
  [ -z "$EDVOL" ] && [ -n "$ED" ] && EDVOL="$v"
  CMNAME=$(k -n "$NS" get deploy "$DEP" \
           -o jsonpath="{.spec.template.spec.volumes[?(@.name==\"$v\")].configMap.name}" 2>/dev/null)
  [ "$CMNAME" = "app-config" ] && [ -z "$CMVOL" ] && CMVOL="$v"
done

if [ -n "$EDVOL" ]; then
  ok "the Deployment has an emptyDir volume ('$EDVOL')"
else
  bad "the Deployment has an emptyDir volume"
fi

if [ -n "$CMVOL" ]; then
  ok "the Deployment mounts the ConfigMap app-config as a volume ('$CMVOL')"
else
  bad "the Deployment mounts the ConfigMap app-config as a volume"
fi

# ---- the init container ----
ICN=$(k -n "$NS" get deploy "$DEP" \
      -o jsonpath='{range .spec.template.spec.initContainers[*]}{.name}{"\n"}{end}' 2>/dev/null \
      | tr -d '\r' | grep -v '^[[:space:]]*$')
NIC=$(printf '%s\n' "$ICN" | grep -c '[^[:space:]]')
if [ "$NIC" -ge 1 ] 2>/dev/null; then
  ok "the Deployment has at least one init container ($NIC)"
else
  bad "the Deployment has at least one init container (got $NIC)"
fi

GOT_ED=0; GOT_CM=0; GOT_PATH=0; GOT_SRC=0
for c in $ICN; do
  MP=$(k -n "$NS" get deploy "$DEP" \
       -o jsonpath="{.spec.template.spec.initContainers[?(@.name==\"$c\")].volumeMounts[?(@.name==\"$EDVOL\")].mountPath}" 2>/dev/null)
  [ "$MP" = "/etc/app" ] && GOT_ED=1

  CMPATH=$(k -n "$NS" get deploy "$DEP" \
           -o jsonpath="{.spec.template.spec.initContainers[?(@.name==\"$c\")].volumeMounts[?(@.name==\"$CMVOL\")].mountPath}" 2>/dev/null)
  if [ -n "$CMPATH" ]; then
    GOT_CM=1
    CMD=$(k -n "$NS" get deploy "$DEP" \
          -o jsonpath="{.spec.template.spec.initContainers[?(@.name==\"$c\")].command}" 2>/dev/null)
    case "$CMD" in
      *"/etc/app"*) GOT_PATH=1;;
    esac
    case "$CMD" in
      *"$CMPATH"*|*"config.yaml"*) GOT_SRC=1;;
    esac
  fi
done

if [ "$GOT_ED" -eq 1 ]; then
  ok "an init container mounts the emptyDir at /etc/app"
else
  bad "an init container mounts the emptyDir at /etc/app"
fi

if [ "$GOT_CM" -eq 1 ]; then
  ok "an init container mounts the ConfigMap so it can read the value"
else
  bad "an init container mounts the ConfigMap so it can read the value"
fi

if [ "$GOT_PATH" -eq 1 ]; then
  ok "the init container's command writes into /etc/app"
else
  bad "the init container's command writes into /etc/app"
fi

if [ "$GOT_SRC" -eq 1 ]; then
  ok "the init container's command reads the ConfigMap's key"
else
  bad "the init container's command reads the ConfigMap's key"
fi

# ---- the main container ----
MCN=$(k -n "$NS" get deploy "$DEP" \
      -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{"\n"}{end}' 2>/dev/null \
      | tr -d '\r' | grep -v '^[[:space:]]*$')
MAIN=""
for c in $MCN; do
  C=$(k -n "$NS" get deploy "$DEP" \
      -o jsonpath="{.spec.template.spec.containers[?(@.name==\"$c\")].command}" 2>/dev/null)
  case "$C" in
    *config.yaml*) MAIN="$c"; break;;
  esac
done
[ -z "$MAIN" ] && MAIN=$(printf '%s\n' "$MCN" | head -1)
if [ -n "$MAIN" ]; then
  ok "the main container is '$MAIN'"

  MMP=$(k -n "$NS" get deploy "$DEP" \
        -o jsonpath="{.spec.template.spec.containers[?(@.name==\"$MAIN\")].volumeMounts[?(@.name==\"$EDVOL\")].mountPath}" 2>/dev/null)
  eq "the main container mounts the emptyDir at /etc/app" "$MMP" "/etc/app"

  MCMP=$(k -n "$NS" get deploy "$DEP" \
         -o jsonpath="{.spec.template.spec.containers[?(@.name==\"$MAIN\")].volumeMounts[?(@.name==\"$CMVOL\")].mountPath}" 2>/dev/null)
  nonempty "the main container mounts the ConfigMap too" "$MCMP"

  MRO=$(k -n "$NS" get deploy "$DEP" \
        -o jsonpath="{.spec.template.spec.containers[?(@.name==\"$MAIN\")].volumeMounts[?(@.name==\"$CMVOL\")].readOnly}" 2>/dev/null)
  if [ "$MRO" = "true" ]; then
    ok "the ConfigMap is mounted read-only in the main container"
  elif [ -z "$MRO" ]; then
    ok "the ConfigMap is mounted read-only in the main container (ConfigMap volumes are read-only anyway)"
  else
    bad "the ConfigMap is mounted read-only in the main container (readOnly '$MRO')"
  fi
else
  bad "there is a main container"
fi

# ---- the workload ----
READYREP=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
eq "the Deployment has 1 ready replica" "$READYREP" "1"

# ---- and the file really is there, with the right content ----
echo "Reading /etc/app/config.yaml from inside the main container..."
OUT=""
i=0
while [ "$i" -lt 30 ]; do
  OUT=$(k -n "$NS" exec deploy/"$DEP" -- cat /etc/app/config.yaml 2>/dev/null) || OUT=""
  if [ -z "$OUT" ] && [ -n "$MAIN" ]; then
    OUT=$(k -n "$NS" exec deploy/"$DEP" -c "$MAIN" -- cat /etc/app/config.yaml 2>/dev/null) || OUT=""
  fi
  [ -n "$OUT" ] && break
  sleep 2
  i=$((i+2))
done
has "the main container reads the ConfigMap's value from /etc/app/config.yaml" "$OUT" "mode: production"

note "An init container's job is to prepare something the main containers need,"
note "and it must finish successfully before they start. A file written into an"
note "init container's own filesystem is gone by the time the main container"
note "runs - it has to be a shared volume."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}v2 PASSED${X}"; else echo -e "${R}v2 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
