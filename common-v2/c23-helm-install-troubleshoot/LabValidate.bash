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

NS=webapps
RELEASE=broken
WORK=/tmp/cka-lab/charts/broken-chart
TPL="$WORK/templates/deployment.yaml"
BAD_TAG=0.0.0-does-not-exist
BAD_IMAGE=nginx:$BAD_TAG

echo "== c23: Install a chart and fix it when it fails =="

# ---- the release itself ----
HL=$(helm list -n "$NS" --all 2>/dev/null)
ROW=$(printf '%s\n' "$HL" | awk '$1=="broken"{print; exit}')
if [ -z "$ROW" ]; then
  bad "helm list -n $NS shows a release named $RELEASE (it does not)"
  skip "the release status check (there is no release $RELEASE in $NS)"
else
  ok "helm list -n $NS shows a release named $RELEASE"
  has "the release $RELEASE has STATUS deployed" "$ROW" "deployed"
fi

HSTATUS=$(helm status "$RELEASE" -n "$NS" 2>/dev/null)
if [ -z "$HSTATUS" ]; then
  bad "helm status $RELEASE -n $NS succeeds (it returned nothing)"
  skip "the helm status report check (helm status returned nothing)"
else
  ok "helm status $RELEASE -n $NS succeeds"
  has "helm status reports the release as deployed" "$HSTATUS" "deployed"
fi

# ---- the Deployment the chart creates ----
DEP=$(k -n "$NS" get deploy broken-chart -o jsonpath='{.metadata.name}' 2>/dev/null)
if [ -z "$DEP" ]; then
  # Fall back to the release's labels, in case the candidate renamed it.
  DEP=$(k -n "$NS" get deploy -l "app.kubernetes.io/instance=$RELEASE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
fi

if [ -z "$DEP" ]; then
  bad "the chart's Deployment exists in namespace $NS (no Deployment named broken-chart and none labelled for the release)"
  skip "the replica / image / pod checks (the chart's Deployment was not found)"
else
  ok "the chart's Deployment ($DEP) exists in namespace $NS"

  eq "the Deployment asks for 1 replica" \
    "$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.replicas}' 2>/dev/null)" "1"

  eq "the Deployment has 1 ready replica" \
    "$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" "1"

  IMG=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.containers[*].image}' 2>/dev/null)
  if [ -z "$IMG" ]; then
    bad "the Deployment runs a container image (it has no container image)"
  elif [ "$IMG" = "$BAD_IMAGE" ]; then
    bad "the container image is not the broken one (got '$IMG')"
  else
    ok "the container image is not the broken one ($IMG)"
  fi

  # ---- every pod of the Deployment must be Running ----
  SEL=$(k -n "$NS" get deploy "$DEP" -o go-template='{{range $k,$v := .spec.selector.matchLabels}}{{$k}}={{$v}},{{end}}' 2>/dev/null | sed 's/,$//')
  PHASES=$(k -n "$NS" get pods -l "$SEL" -o jsonpath='{range .items[*]}{.status.phase}{" "}{end}' 2>/dev/null)
  if [ -z "$(printf '%s' "$PHASES" | tr -d ' ')" ]; then
    bad "the Deployment has pods (none found with selector '$SEL')"
  else
    ok "the Deployment has pods (selector '$SEL')"
    NOTRUN=$(printf '%s' "$PHASES" | tr ' ' '\n' | grep -v '^Running$' | grep -v '^$' | wc -l | tr -d ' ')
    eq "every pod of the Deployment is Running" "$NOTRUN" "0"
  fi
fi

# ---- the chart on disk no longer carries the fault ----
if [ ! -f "$TPL" ]; then
  bad "the chart's template file $TPL exists"
elif grep -q "$BAD_TAG" "$TPL"; then
  bad "the chart's template no longer contains the broken image tag (it still contains '$BAD_IMAGE')"
else
  ok "the chart's template no longer contains the broken image tag"
fi

note "helm install reports success even when the workload it creates is broken:"
note "Helm only knows that the objects were created, not that they work."
note "The diagnosis is helm status, kubectl get pods -n $NS and the pod's events."
note "Editing the chart on disk changes nothing until the next helm upgrade."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c23 PASSED${X}"; else echo -e "${R}c23 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
