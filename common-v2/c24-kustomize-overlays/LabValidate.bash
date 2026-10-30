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
DEV="$ROOT/overlays/dev"
PROD="$ROOT/overlays/prod"
DEV_K="$DEV/kustomization.yaml"
PROD_K="$PROD/kustomization.yaml"

# awk programs that read the manifest kustomize builds. They are kept as
# variables rather than functions so the helpers above stay as they are.
AWK_DEP='BEGIN{RS="\n---\n"}
{
  n=split($0,L,"\n"); keep=0
  for(i=1;i<=n;i++) if (L[i] ~ /^kind:[[:space:]]*Deployment[[:space:]]*$/) keep=1
  if(keep) print $0
}'
AWK_NAME='/^metadata:/{m=1; next}
m && /^[^[:space:]]/{m=0}
m && /^[[:space:]]+name:[[:space:]]*/{gsub(/[[:space:]]/,"",$2); print $2; exit}'
AWK_REPL='/^[[:space:]]*replicas:[[:space:]]*[0-9]+/{gsub(/[[:space:]]/,"",$2); print $2; exit}'
AWK_IMAGE='/^[[:space:]]*(-[[:space:]]*)?image:[[:space:]]*/{sub(/^[[:space:]]*(-[[:space:]]*)?image:[[:space:]]*/,""); gsub(/"/,""); print; exit}'

echo "== c24: One base, two environments =="

# ---- both overlays exist and both use the base ----
if [ -f "$DEV_K" ]; then
  ok "the dev overlay has a kustomization.yaml"
  if grep -qE '(\.\./\.\./base|/tmp/cka-lab/kustomize/base)' "$DEV_K"; then
    ok "the dev overlay references the base with a resources entry"
  else
    bad "the dev overlay references the base with a resources entry (nothing in $DEV_K points at ../../base)"
  fi
else
  bad "the dev overlay has a kustomization.yaml ($DEV_K)"
  skip "the dev overlay's base-reference check (no kustomization.yaml)"
fi

if [ -f "$PROD_K" ]; then
  ok "the prod overlay has a kustomization.yaml"
  if grep -qE '(\.\./\.\./base|/tmp/cka-lab/kustomize/base)' "$PROD_K"; then
    ok "the prod overlay references the base with a resources entry"
  else
    bad "the prod overlay references the base with a resources entry (nothing in $PROD_K points at ../../base)"
  fi
else
  bad "the prod overlay has a kustomization.yaml ($PROD_K)"
  skip "the prod overlay's base-reference check (no kustomization.yaml)"
fi

# ---- the dev overlay builds into the right Deployment ----
BUILD_DEV=$(kubectl kustomize "$DEV" 2>/dev/null)
if [ -z "$BUILD_DEV" ]; then
  bad "the dev overlay builds (kubectl kustomize $DEV produced no output)"
  skip "the dev overlay's Deployment name / replica / image checks (the overlay does not build)"
else
  ok "the dev overlay builds (kubectl kustomize $DEV)"
  DOC=$(printf '%s\n' "$BUILD_DEV" | awk "$AWK_DEP")
  if [ -z "$DOC" ]; then
    bad "the dev overlay builds a Deployment (it builds none)"
    skip "the dev overlay's Deployment name / replica / image checks (no Deployment in the output)"
  else
    eq "the dev overlay's Deployment is named app" \
      "$(printf '%s\n' "$DOC" | awk "$AWK_NAME")" "app"
    eq "the dev overlay's Deployment has exactly 1 replica" \
      "$(printf '%s\n' "$DOC" | awk "$AWK_REPL")" "1"
    eq "the dev overlay's Deployment runs nginx:1.25" \
      "$(printf '%s\n' "$DOC" | awk "$AWK_IMAGE")" "nginx:1.25"
  fi
fi

# ---- the prod overlay builds into the right Deployment ----
BUILD_PROD=$(kubectl kustomize "$PROD" 2>/dev/null)
if [ -z "$BUILD_PROD" ]; then
  bad "the prod overlay builds (kubectl kustomize $PROD produced no output)"
  skip "the prod overlay's Deployment name / replica / image checks (the overlay does not build)"
else
  ok "the prod overlay builds (kubectl kustomize $PROD)"
  DOC=$(printf '%s\n' "$BUILD_PROD" | awk "$AWK_DEP")
  if [ -z "$DOC" ]; then
    bad "the prod overlay builds a Deployment (it builds none)"
    skip "the prod overlay's Deployment name / replica / image checks (no Deployment in the output)"
  else
    eq "the prod overlay's Deployment is named app" \
      "$(printf '%s\n' "$DOC" | awk "$AWK_NAME")" "app"
    eq "the prod overlay's Deployment has exactly 3 replicas" \
      "$(printf '%s\n' "$DOC" | awk "$AWK_REPL")" "3"
    eq "the prod overlay's Deployment runs nginx:1.26" \
      "$(printf '%s\n' "$DOC" | awk "$AWK_IMAGE")" "nginx:1.26"
  fi
fi

# ---- the dev overlay is the one that was applied ----
APP_NSS=$(k get deploy -A -o jsonpath='{range .items[?(@.metadata.name=="app")]}{.metadata.namespace}{" "}{end}' 2>/dev/null)
APP_NS=""
FIRST_NS=""
for ns in $APP_NSS; do
  [ -z "$FIRST_NS" ] && FIRST_NS="$ns"
  RDY=$(k -n "$ns" get deploy app -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  IMG=$(k -n "$ns" get deploy app -o jsonpath='{.spec.containers[*].image}' 2>/dev/null)
  if [ "$RDY" = "1" ] && [ "$IMG" = "nginx:1.25" ]; then
    APP_NS="$ns"
    break
  fi
done
if [ -z "$APP_NS" ]; then
  APP_NS="$FIRST_NS"
fi

if [ -z "$APP_NS" ]; then
  bad "a Deployment named app is running in the cluster (the dev overlay was not applied)"
  skip "the applied Deployment's replica / ready / image checks (no Deployment named app)"
else
  ok "a Deployment named app is running in the cluster (namespace $APP_NS)"

  eq "the applied Deployment has 1 replica" \
    "$(k -n "$APP_NS" get deploy app -o jsonpath='{.spec.replicas}' 2>/dev/null)" "1"

  eq "the applied Deployment has 1 ready replica" \
    "$(k -n "$APP_NS" get deploy app -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" "1"

  eq "the applied Deployment runs nginx:1.25" \
    "$(k -n "$APP_NS" get deploy app -o jsonpath='{.spec.containers[*].image}' 2>/dev/null)" "nginx:1.25"
fi

note "kubectl kustomize is built into kubectl, so there is nothing to install."
note "An overlay refers to the base with a relative path (../../base), and the"
note "patch that changes the image or the replica count has to target the"
note "Deployment app - a patch that names the wrong kind or the wrong name"
note "does nothing at all, and the build still succeeds."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c24 PASSED${X}"; else echo -e "${R}c24 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
