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

CRD=widgets.example.com
NS=custom
W=w1

echo "== c22: Define a CRD and use it =="

if ! exists "CustomResourceDefinition $CRD exists" crd "$CRD"; then
  echo; echo -e "${R}c22 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the shape of the CRD ----
GROUP=$(k get crd "$CRD" -o jsonpath='{.spec.group}' 2>/dev/null)
eq "the CRD group is example.com" "$GROUP" "example.com"

KIND=$(k get crd "$CRD" -o jsonpath='{.spec.names.kind}' 2>/dev/null)
eq "the CRD kind is Widget" "$KIND" "Widget"

PLURAL=$(k get crd "$CRD" -o jsonpath='{.spec.names.plural}' 2>/dev/null)
eq "the CRD plural name is widgets" "$PLURAL" "widgets"

SINGULAR=$(k get crd "$CRD" -o jsonpath='{.spec.names.singular}' 2>/dev/null)
eq "the CRD singular name is widget" "$SINGULAR" "widget"

SCOPE=$(k get crd "$CRD" -o jsonpath='{.spec.scope}' 2>/dev/null)
eq "the CRD scope is Namespaced" "$SCOPE" "Namespaced"

VERSIONS=$(k get crd "$CRD" -o jsonpath='{.spec.versions[*].name}' 2>/dev/null)
has "the CRD serves the version v1" "$VERSIONS" "v1"

# ---- the schema ----
PROPS=$(k get crd "$CRD" -o jsonpath='{.spec.versions[?(@.name=="v1")].schema.openAPIV3Schema.properties}' 2>/dev/null)
has "the v1 schema declares a spec property" "$PROPS" "spec"

REQ=$(k get crd "$CRD" -o jsonpath='{.spec.versions[?(@.name=="v1")].schema.openAPIV3Schema.properties.spec.required}' 2>/dev/null)
REQTOK=$(printf '%s' "$REQ" | tr -d '[]' | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -x 'size' | head -1)
nonempty "the spec schema REQUIRES size" "$REQTOK"

SIZE_TYPE=$(k get crd "$CRD" -o jsonpath='{.spec.versions[?(@.name=="v1")].schema.openAPIV3Schema.properties.spec.properties.size.type}' 2>/dev/null)
eq "the size property is typed string" "$SIZE_TYPE" "string"

# ---- the CRD has to be served before kubectl can talk to it ----
i=0
while [ $i -lt 30 ]; do
  if k get widgets -n "$NS" >/dev/null 2>&1; then break; fi
  i=$((i+1)); sleep 2
done

ESTABLISHED=$(k get crd "$CRD" -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' 2>/dev/null)
eq "the CRD is Established" "$ESTABLISHED" "True"

# ---- the Widget ----
if k get widgets "$W" -n "$NS" >/dev/null 2>&1; then
  ok "Widget $W exists in namespace $NS"

  SIZE=$(k get widgets "$W" -n "$NS" -o jsonpath='{.spec.size}' 2>/dev/null)
  eq "the Widget has spec.size: large" "$SIZE" "large"
else
  bad "Widget $W exists in namespace $NS"
fi

# ---- kubectl get widgets has to work ----
LIST=$(k get widgets -n "$NS" 2>&1)
LIST_RC=$?
if [ "$LIST_RC" -eq 0 ]; then
  ok "kubectl get widgets works"
else
  bad "kubectl get widgets works (got '$LIST')"
fi
has "kubectl get widgets lists the Widget w1" "$LIST" "w1"

note "The plural in the CRD's names is what makes 'kubectl get widgets' work;"
note "the API server registers the resource under the plural, not the kind."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c22 PASSED${X}"; else echo -e "${R}c22 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
