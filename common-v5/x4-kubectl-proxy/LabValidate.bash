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
NAMELIST="$LABDIR/x4.namespaces"

echo "== x4: Ask the API server directly =="

# ---- the namespaces the setup created ---------------------------------------

NSLIST=""
if [ -f "$NAMELIST" ]; then
  NSLIST=$(tr '\n' ' ' < "$NAMELIST" | tr -s ' ')
fi
if [ -z "$NSLIST" ]; then
  NSLIST="cka-proxy-alpha cka-proxy-beta"
fi

# ---- the answer file --------------------------------------------------------

target_file(){
  local name=$1
  if [ -f "/root/$name" ]; then printf '%s\n' "/root/$name"
  elif [ -f "$HOME/$name" ]; then printf '%s\n' "$HOME/$name"
  else printf '%s\n' "/root/$name"; fi
}

FILE=$(target_file namespaces.json)

if [ -f "$FILE" ]; then
  ok "the response file $FILE exists"
else
  bad "the response file $FILE exists"
fi

SIZE=0
[ -f "$FILE" ] && SIZE=$(wc -c < "$FILE" 2>/dev/null | tr -d ' ')
if [ "${SIZE:-0}" -gt 0 ] 2>/dev/null; then
  ok "the response file is not empty ($SIZE bytes)"
else
  bad "the response file is not empty (it is ${SIZE:-0} bytes)"
fi

# ---- it is JSON -------------------------------------------------------------

FIRST=""
[ -f "$FILE" ] && FIRST=$(tr -d ' \t\r\n' < "$FILE" 2>/dev/null | head -c 1)
case "$FIRST" in
  '{'|'[') ok "the response is JSON (it starts with '$FIRST')";;
  *) bad "the response is JSON (it starts with '${FIRST:-<nothing>}')";;
esac

# ---- it holds an items array ------------------------------------------------

if [ -f "$FILE" ] && grep -qE '"items"[[:space:]]*:[[:space:]]*\[' "$FILE" 2>/dev/null; then
  ok "the response holds an items array"
else
  bad "the response holds an items array"
fi

# ---- how many namespaces are in it ------------------------------------------

COUNT=""
COUNTED_BY=""
if [ -f "$FILE" ] && command -v python3 >/dev/null 2>&1; then
  COUNT=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); i=d.get("items") if isinstance(d,dict) else None; print(len(i) if isinstance(i,list) else -1)' "$FILE" 2>/dev/null)
  COUNTED_BY="parsed out of the JSON"
fi
if [ -z "$COUNT" ] || [ "$COUNT" = "-1" ]; then
  if [ -f "$FILE" ]; then
    COUNT=$(grep -oE '"kind"[[:space:]]*:[[:space:]]*"Namespace"' "$FILE" 2>/dev/null | wc -l | tr -d ' ')
    COUNTED_BY="counted from the Namespace entries in the file"
  fi
fi

LIVE=$(k get namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')

if [ -z "$COUNT" ]; then
  skip "the response lists every namespace (the file could not be parsed)"
elif [ -z "$LIVE" ]; then
  skip "the response lists every namespace (the cluster's namespace list could not be read)"
else
  eq "the response lists every namespace in the cluster ($COUNTED_BY)" "$COUNT" "$LIVE"
fi

# ---- and it names the namespaces the setup created --------------------------

for NS in $NSLIST; do
  [ -n "$NS" ] || continue
  if [ -f "$FILE" ] && grep -qE "\"name\"[[:space:]]*:[[:space:]]*\"$NS\"" "$FILE" 2>/dev/null; then
    ok "the response names the namespace $NS"
  else
    bad "the response names the namespace $NS"
  fi
done

note "kubectl proxy serves the API under /api and /apis. The namespaces"
note "collection is at /api/v1/namespaces, and the port defaults to 8001."
note "The top-level object is a NamespaceList; the namespaces are in items."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}x4 PASSED${X}"; else echo -e "${R}x4 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
