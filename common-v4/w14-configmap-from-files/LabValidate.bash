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

NS=cfg
CM=colors
DEP=cfg-app
DIR=/tmp/cka-lab/colors/primary

# The expected content of a key. It is read from the file the setup wrote, so
# the grader compares the ConfigMap against the files rather than against a
# second hard-coded copy of them. If the directory has gone, the built-in
# fallback is used.
expect(){
  if [ -f "$DIR/$1" ]; then
    cat "$DIR/$1"
  else
    case "$1" in
      cyan)    printf '%s' "cyan" ;;
      magenta) printf '%s' "magenta" ;;
      yellow)  printf '%s' "yellow" ;;
      blue)    printf '%s' "blue" ;;
      black)   printf '%s\nknown as key' "black" ;;
    esac
  fi
}

cmval(){
  k -n "$NS" get configmap "$CM" -o jsonpath="{.data.$1}" 2>/dev/null
}

echo "== w14: A ConfigMap made of files =="

# ---- 1. the ConfigMap --------------------------------------------------------

if ! k get configmap "$CM" -n "$NS" >/dev/null 2>&1; then
  bad "ConfigMap $CM exists in namespace $NS"
  skip "the key checks (there is no ConfigMap $CM)"
  skip "the value checks (there is no ConfigMap $CM)"
else
  ok "ConfigMap $CM exists in namespace $NS"

  KEYS=$(k -n "$NS" get configmap "$CM" -o jsonpath='{range $k, $v := .data}{$k}{"\n"}{end}' 2>/dev/null | grep -c . || true)
  eq "the ConfigMap has exactly five keys" "${KEYS:-0}" "5"

  for key in cyan magenta yellow blue; do
    GOT=$(cmval "$key")
    eq "the value of '$key' is the content of the file '$key'" "$GOT" "$(expect "$key")"
  done

  BLACK=$(cmval black)
  if [ -n "$BLACK" ]; then
    has "the value of 'black' holds the line 'known as key'" "$BLACK" "known as key"
    LINES=$(printf '%s\n' "$BLACK" | grep -c . || true)
    eq "the value of 'black' has two lines, not two keys" "${LINES:-0}" "2"
    eq "the value of 'black' is the whole content of the file 'black'" "$BLACK" "$(expect black)"
  else
    bad "the value of 'black' holds the line 'known as key' (the key is missing or empty)"
  fi
fi

# ---- 2. the Deployment ------------------------------------------------------

if ! k get deployment "$DEP" -n "$NS" >/dev/null 2>&1; then
  bad "Deployment $DEP exists in namespace $NS"
  skip "the envFrom check (there is no Deployment $DEP)"
  skip "the replica checks (there is no Deployment $DEP)"
  skip "the live check (there is no Deployment $DEP)"
else
  ok "Deployment $DEP exists in namespace $NS"

  REP=$(k -n "$NS" get deployment "$DEP" -o jsonpath='{.spec.replicas}' 2>/dev/null)
  eq "the Deployment asks for 1 replica" "${REP:-}" "1"

  IMG=$(k -n "$NS" get deployment "$DEP" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
  case "$IMG" in
    nginx|nginx:*) ok "the Deployment runs the image nginx (got '$IMG')" ;;
    *) bad "the Deployment runs the image nginx (got '$IMG')" ;;
  esac

  ENVFROM=$(k -n "$NS" get deployment "$DEP" -o jsonpath='{.spec.template.spec.containers[0].envFrom[0].configMapRef.name}' 2>/dev/null)
  if [ "$ENVFROM" = "$CM" ]; then
    ok "the pod template imports the ConfigMap $CM with envFrom"
  else
    bad "the pod template imports the ConfigMap $CM with envFrom (got '${ENVFROM:-nothing}')"
  fi

  # Give the rollout a moment, so the live check is not racing the kubelet.
  i=0
  READY=""
  while [ "$i" -lt 45 ]; do
    READY=$(k -n "$NS" get deployment "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null) || READY=""
    [ "${READY:-0}" = "1" ] && break
    sleep 2
    i=$((i+2))
  done
  eq "the Deployment has 1 ready replica" "${READY:-0}" "1"
fi

# ---- 3. the live check ------------------------------------------------------

if ! k get deployment "$DEP" -n "$NS" >/dev/null 2>&1; then
  :
else
  LIVE=$(k -n "$NS" exec "deploy/$DEP" -- printenv cyan 2>/dev/null)
  if [ -z "$LIVE" ]; then
    OWN=$(k -n "$NS" get deployment "$DEP" -o jsonpath='{.metadata.uid}' 2>/dev/null)
    JP="{range .items[*]}{.metadata.ownerReferences[?(@.uid==\"$OWN\")].name}{\"\n\"}{end}"
    POD=$(k -n "$NS" get pods -o jsonpath="$JP" 2>/dev/null | grep -v '^$' | head -1)
    [ -n "$POD" ] && LIVE=$(k -n "$NS" exec "$POD" -- printenv cyan 2>/dev/null)
  fi
  if [ -z "$LIVE" ]; then
    bad "inside the pod, printenv cyan prints the content of the file cyan (nothing came back)"
    note "The command to run is:"
    note "  kubectl -n $NS exec deploy/$DEP -- printenv cyan"
  else
    eq "inside the pod, printenv cyan prints the content of the file cyan" "$LIVE" "$(expect cyan)"
  fi
fi

note "kubectl create configmap --from-file uses the FILE NAME as the key and"
note "the FILE CONTENTS as the value. A file with two lines makes one key with"
note "a two-line value - it is not split into two keys."
note "envFrom imports every key of the ConfigMap as an environment variable"
note "named after the key, which is why all five keys show up at once."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}w14 PASSED${X}"; else echo -e "${R}w14 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
