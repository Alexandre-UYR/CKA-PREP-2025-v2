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

FILE=/root/argo-helm.yaml
REPO_URL=https://argoproj.github.io/argo-helm

echo "== Q2: Argo CD with Helm, CRDs excluded =="

# Note: the task only asks for the manifest to be GENERATED, never applied.
# Nothing in Argo CD is installed, so there are no Argo CD pods to look for.

# --- The generated manifest ----------------------------------------------
if [ -f "$FILE" ]; then
  ok "$FILE exists"
else
  bad "$FILE exists (file not found)"
fi
CONTENT="$(cat "$FILE" 2>/dev/null)"
SIZE="$(printf '%s' "$CONTENT" | wc -c | tr -d ' ')"
if [ "${SIZE:-0}" -gt 0 ] 2>/dev/null; then
  ok "$FILE is not empty ($SIZE bytes)"
else
  bad "$FILE is not empty (got $SIZE bytes)"
fi

CRDS="$(grep -c 'kind: CustomResourceDefinition' "$FILE" 2>/dev/null || true)"
eq "The generated manifest contains no CustomResourceDefinition (crds.install=false)" "${CRDS:-0}" "0"

has "The generated manifest contains the argocd-server workload" "$CONTENT" "name: argocd-server"
has "The generated manifest contains a Deployment" "$CONTENT" "kind: Deployment"

# Every namespaced object in the file must live in the argocd namespace.
# Helm quotes some namespace values ("argocd") and the CRD schemas contain
# bare "namespace:" property names, so quotes are stripped and empty values
# are ignored.
OTHER_NS="$(grep -h -E '^[[:space:]]*namespace:[[:space:]]*' "$FILE" 2>/dev/null \
  | sed -E 's/.*namespace:[[:space:]]*//' | tr -d '"' | sed -E 's/[[:space:]]+$//' \
  | grep -v '^$' | grep -v '^argocd$' | sort -u | tr '\n' ' ')"
eq "Every namespaced object in the manifest is in the argocd namespace" "$OTHER_NS" ""
has "The manifest places objects in the argocd namespace" "$CONTENT" "namespace: argocd"

# --- The namespace --------------------------------------------------------
exists "Namespace argocd exists" ns argocd

# --- The helm repo --------------------------------------------------------
REPO_LINE="$(helm repo list 2>/dev/null | awk 'NR>1 && $1=="argocd" {print $2; exit}')"
eq "Helm repo 'argocd' points at $REPO_URL" "$REPO_LINE" "$REPO_URL"

if [ "$FAILS" -eq 0 ]; then echo -e "${G}Q2 PASSED${X}"; else echo -e "${R}Q2 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
