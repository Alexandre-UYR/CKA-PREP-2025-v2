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

ROOT=/tmp/cka-lab/kustomize
DEVDIR="$ROOT/overlays/dev"
PRODDIR="$ROOT/overlays/prod"
NS=dev

# Picks one document out of a rendered Kustomize build: the document whose
# "kind:" is $1 and whose metadata "name:" is $2. The rendered YAML arrives on
# stdin.
kdoc(){
  awk -v k="$1" -v n="$2" '
    function flush(   i, kindhit, namehit, nl) {
      kindhit = 0; namehit = 0
      nl = split(doc, L, "\n")
      for (i = 1; i <= nl; i++) {
        if (L[i] == "kind: " k) kindhit = 1
        if (L[i] == "  name: " n) namehit = 1
      }
      if (kindhit && namehit) printf "%s", doc
      doc = ""
    }
    /^---[[:space:]]*$/ { flush(); next }
    { doc = doc $0 "\n" }
    END { flush() }
  '
}

# The value of a top-level field of a rendered document.
field(){
  # $1 = document, $2 = field name
  printf '%s\n' "$1" | grep -E "^  $2: " | head -1 | sed "s/^  $2:[[:space:]]*//" | tr -d '"'
}

# The image of the first container of a rendered Deployment. The line may be
# "  image: nginx:1.25" or "  - image: nginx:1.25", depending on how the
# container list was written.
image_of(){
  printf '%s\n' "$1" | grep -E "^[[:space:]]+(-[[:space:]]+)?image: " | head -1 \
    | sed 's/.*image:[[:space:]]*//' | tr -d '"'
}

echo "== w15: The overlay that does nothing =="

DEVERR=$(mktemp)
PRODERR=$(mktemp)

if ! command -v kubectl >/dev/null 2>&1; then
  bad "kubectl is on the PATH"
  skip "the dev overlay build checks (kubectl is not on the PATH)"
  skip "the prod overlay build checks (kubectl is not on the PATH)"
  skip "the applied-dev checks (kubectl is not on the PATH)"
  rm -f "$DEVERR" "$PRODERR"
  echo
  if [ "$FAILS" -eq 0 ]; then echo -e "${G}w15 PASSED${X}"; else echo -e "${R}w15 FAILED ($FAILS checks)${X}"; fi
  exit $(( FAILS > 0 ))
fi

# ---- the dev overlay --------------------------------------------------------

if [ ! -f "$DEVDIR/kustomization.yaml" ]; then
  bad "the dev overlay has a kustomization.yaml"
  skip "the dev overlay build checks (there is no $DEVDIR/kustomization.yaml)"
else
  ok "the dev overlay has a kustomization.yaml"

  # The build's stdout is the YAML; its stderr carries warnings (the
  # `patchesStrategicMerge` field is deprecated and says so) and errors. They
  # are kept apart so that the YAML is not polluted.
  DEVERR=$(mktemp)
  DEVBUILD=$(kubectl kustomize "$DEVDIR" 2>"$DEVERR")
  DEVRC=$?
  if [ "$DEVRC" -ne 0 ]; then
    bad "kubectl kustomize builds the dev overlay"
    note "it said: $(grep -v '^# Warning' "$DEVERR" | head -3 | tr '\n' ' ')"
    skip "the dev Deployment checks (the build failed)"
  else
    ok "kubectl kustomize builds the dev overlay"

    NDEP=$(printf '%s\n' "$DEVBUILD" | grep -c '^kind: Deployment$' || true)
    eq "the dev overlay builds exactly one Deployment" "${NDEP:-0}" "1"

    DEVDOC=$(printf '%s\n' "$DEVBUILD" | kdoc Deployment app)
    if [ -z "$DEVDOC" ]; then
      bad "the dev overlay builds a Deployment named app"
    else
      ok "the dev overlay builds a Deployment named app"

      eq "the dev Deployment asks for 1 replica" "$(field "$DEVDOC" replicas)" "1"
      eq "the dev Deployment runs nginx:1.25" "$(image_of "$DEVDOC")" "nginx:1.25"
      eq "the dev Deployment is in namespace dev" "$(field "$DEVDOC" namespace)" "dev"
    fi
  fi
fi

# ---- the prod overlay -------------------------------------------------------

if [ ! -f "$PRODDIR/kustomization.yaml" ]; then
  bad "the prod overlay has a kustomization.yaml (in $PRODDIR)"
  skip "the prod overlay build checks (there is no $PRODDIR/kustomization.yaml)"
else
  ok "the prod overlay has a kustomization.yaml"

  PRODBUILD=$(kubectl kustomize "$PRODDIR" 2>"$PRODERR")
  PRODRC=$?
  if [ "$PRODRC" -ne 0 ]; then
    bad "kubectl kustomize builds the prod overlay"
    note "it said: $(grep -v '^# Warning' "$PRODERR" | head -3 | tr '\n' ' ')"
    skip "the prod Deployment checks (the build failed)"
    skip "the prod Service check (the build failed)"
  else
    ok "kubectl kustomize builds the prod overlay"

    NDEP=$(printf '%s\n' "$PRODBUILD" | grep -c '^kind: Deployment$' || true)
    eq "the prod overlay builds exactly one Deployment" "${NDEP:-0}" "1"

    PRODDOC=$(printf '%s\n' "$PRODBUILD" | kdoc Deployment app)
    if [ -z "$PRODDOC" ]; then
      bad "the prod overlay builds a Deployment named app"
    else
      ok "the prod overlay builds a Deployment named app"
      eq "the prod Deployment asks for 3 replicas" "$(field "$PRODDOC" replicas)" "3"
      eq "the prod Deployment runs nginx:1.26" "$(image_of "$PRODDOC")" "nginx:1.26"
    fi

    PRODSVC=$(printf '%s\n' "$PRODBUILD" | kdoc Service app)
    if [ -z "$PRODSVC" ]; then
      bad "the prod overlay builds a Service named app"
    else
      ok "the prod overlay builds a Service named app"
      eq "the prod Service is of type NodePort" "$(field "$PRODSVC" type)" "NodePort"
    fi
  fi
fi

# ---- the dev overlay, applied -----------------------------------------------

if ! k get deployment app -n "$NS" >/dev/null 2>&1; then
  bad "Deployment app exists in namespace $NS"
  skip "the applied-replica checks (there is no Deployment app in $NS)"
else
  ok "Deployment app exists in namespace $NS"

  REP=$(k -n "$NS" get deployment app -o jsonpath='{.spec.replicas}' 2>/dev/null)
  eq "the applied Deployment asks for 1 replica" "${REP:-}" "1"

  i=0
  READY=""
  while [ "$i" -lt 45 ]; do
    READY=$(k -n "$NS" get deployment app -o jsonpath='{.status.readyReplicas}' 2>/dev/null) || READY=""
    [ "${READY:-0}" = "1" ] && break
    sleep 2
    i=$((i+2))
  done
  eq "the applied Deployment has 1 ready replica" "${READY:-0}" "1"

  IMG=$(k -n "$NS" get deployment app -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
  eq "the applied Deployment runs nginx:1.25" "${IMG:-}" "nginx:1.25"
fi

if k get service app -n "$NS" >/dev/null 2>&1; then
  ok "Service app exists in namespace $NS"
else
  bad "Service app exists in namespace $NS (the whole dev overlay has to be applied)"
fi

note "A patch that names a resource which does not exist in the base does not"
note "do anything: kustomize matches a patch against the resources of the base"
note "by kind and name. The current kustomize stops the build with an error;"
note "older releases ignored the patch and printed the base unchanged."
note "kubectl kustomize is built into kubectl - there is no separate kustomize"
note "binary to install, and it needs no cluster to run."

rm -f "$DEVERR" "$PRODERR"

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}w15 PASSED${X}"; else echo -e "${R}w15 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
