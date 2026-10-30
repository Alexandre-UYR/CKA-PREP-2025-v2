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

echo "== Q14 Storage Class =="

# ---- the class itself ----
if ! exists "StorageClass local-storage exists" sc local-storage; then
  echo; echo -e "${R}Q14 FAILED ($FAILS checks)${X}"; exit 1
fi

eq "provisioner is rancher.io/local-path" \
  "$(k get sc local-storage -o jsonpath='{.provisioner}' 2>/dev/null)" "rancher.io/local-path"

eq "volumeBindingMode is WaitForFirstConsumer" \
  "$(k get sc local-storage -o jsonpath='{.volumeBindingMode}' 2>/dev/null)" "WaitForFirstConsumer"

eq "local-storage is marked as the default class" \
  "$(k get sc local-storage -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' 2>/dev/null)" "true"

# ---- it must be the only default ----
DEFCOUNT=$(k get sc -o jsonpath='{range .items[*]}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null \
  | awk '$1=="true"' | wc -l | tr -d ' ')
eq "exactly one StorageClass is the default" "$DEFCOUNT" "1"

DEFNAME=$(k get sc -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' 2>/dev/null \
  | awk '$2=="true"{print $1}' | head -1)
eq "the default StorageClass is local-storage" "$DEFNAME" "local-storage"

# ---- nothing else was disturbed ----
BEFORE=$(cat /tmp/cka-lab/q14.pvc.before 2>/dev/null)
AFTER=$(k get pvc -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{"="}{.spec.storageClassName}{";"}{end}' 2>/dev/null \
  | tr ';' '\n' | sort)
if [ -z "$BEFORE" ]; then
  echo -e "      NOTE  no PVC snapshot was recorded at setup, skipping the 'claims unchanged' check"
else
  eq "existing PVCs and their StorageClass are unchanged" "$AFTER" "$BEFORE"
fi

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}Q14 PASSED${X}"; else echo -e "${R}Q14 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
