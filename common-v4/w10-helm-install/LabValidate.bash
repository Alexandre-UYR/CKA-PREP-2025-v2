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

NS=apps
RELEASE=hello
CHART=/tmp/cka-lab/charts/hello-world
PRISTINE=/tmp/cka-lab/charts/.pristine-hello-world
VALUES=/root/hello-values.yaml

render_doc(){
  # $1 = kind, $2 = name; the rendered YAML arrives on stdin
  awk -v k="$1" -v n="$2" '
    /^---[[:space:]]*$/ { if (buf ~ k && buf ~ n) print buf; buf=""; next }
    { buf = buf $0 "\n" }
    END { if (buf ~ k && buf ~ n) print buf }
  '
}

echo "== w10: Install a chart, and install it differently =="

# ---- the namespace ----------------------------------------------------------
exists "namespace $NS exists" ns "$NS"

# ---- the values file --------------------------------------------------------

if [ -f "$VALUES" ]; then
  ok "$VALUES exists"
  if [ -s "$VALUES" ]; then
    ok "$VALUES is not empty"
  else
    bad "$VALUES is not empty"
  fi

  # The key is `replicaCount`, so the file has to hold that key at the top
  # level and the value has to be 3. The flattened `replicaCount=3` form is a
  # command-line thing and reads as a different key entirely.
  RV=$(grep -E '^[[:space:]]*replicaCount[[:space:]]*:' "$VALUES" 2>/dev/null | head -1 | sed 's/#.*//' | sed 's/[^0-9]//g')
  if [ -z "$RV" ]; then
    bad "the values file sets replicaCount to 3 (no 'replicaCount:' key found)"
  else
    eq "the values file sets replicaCount to 3" "$RV" "3"
  fi
else
  bad "$VALUES exists (file not found)"
  skip "the replicaCount check (there is no $VALUES)"
fi

# ---- the chart was not edited -----------------------------------------------

if [ ! -d "$CHART" ]; then
  bad "the chart $CHART is on disk"
  skip "the chart-unchanged check (the chart is missing)"
else
  ok "the chart $CHART is on disk"
  if [ -d "$PRISTINE" ]; then
    if diff -r "$PRISTINE" "$CHART" >/dev/null 2>&1; then
      ok "the chart on disk is unchanged (it still matches the pristine copy)"
    else
      bad "the chart on disk is unchanged (the working copy differs from the pristine copy)"
    fi
    CRV=$(grep -E '^[[:space:]]*replicaCount[[:space:]]*:' "$CHART/values.yaml" 2>/dev/null | head -1 | sed 's/#.*//' | sed 's/[^0-9]//g')
    eq "the chart's own values.yaml still sets replicaCount to 1" "$CRV" "1"
  else
    skip "the chart-unchanged check (there is no pristine copy at $PRISTINE)"
  fi
fi

# ---- helm -------------------------------------------------------------------

if ! command -v helm >/dev/null 2>&1; then
  skip "the rendered-chart checks (helm is not on the PATH)"
  skip "the release checks (helm is not on the PATH)"
  echo
  if [ "$FAILS" -eq 0 ]; then echo -e "${G}w10 PASSED${X}"; else echo -e "${R}w10 FAILED ($FAILS checks)${X}"; fi
  exit $(( FAILS > 0 ))
fi

if [ ! -d "$CHART" ]; then
  skip "the rendered-chart checks (the chart is missing)"
  skip "the release checks (the chart is missing)"
else
  # ---- what the chart renders with the values file ----------------------------
  RENDER=$(helm template "$RELEASE" "$CHART" -f "$VALUES" 2>&1)
  if [ -z "$RENDER" ]; then
    bad "helm template renders the chart with the values file"
    skip "the rendered Deployment check"
  elif printf '%s' "$RENDER" | grep -qE '^Error|Error:'; then
    bad "helm template renders the chart with the values file"
    note "helm template said: $(printf '%s' "$RENDER" | head -3 | tr '\n' ' ')"
    skip "the rendered Deployment check"
  else
    ok "helm template renders the chart with the values file"

    DEPLOY_DOC=$(printf '%s\n' "$RENDER" | render_doc "kind: Deployment" "name: hello-world")
    if [ -z "$DEPLOY_DOC" ]; then
      bad "the rendered chart has a Deployment named hello-world"
    else
      ok "the rendered chart has a Deployment named hello-world"
      if printf '%s\n' "$DEPLOY_DOC" | grep -Eq 'replicas:[[:space:]]*3([[:space:]]|$)'; then
        ok "the rendered Deployment has 3 replicas"
      else
        bad "the rendered Deployment has 3 replicas (got: $(printf '%s\n' "$DEPLOY_DOC" | grep -E 'replicas:' | tr -d ' ' | tr '\n' ' '))"
      fi
      if printf '%s\n' "$DEPLOY_DOC" | grep -E 'image:' | grep -q 'nginx:1\.25'; then
        ok "the rendered Deployment runs the image nginx:1.25"
      else
        bad "the rendered Deployment runs the image nginx:1.25 (got: $(printf '%s\n' "$DEPLOY_DOC" | grep -E 'image:' | tr -d ' ' | tr '\n' ' '))"
      fi
    fi
  fi

  # ---- the release itself ----------------------------------------------------
  ROW=$(helm list -n "$NS" --all 2>/dev/null | awk -v r="$RELEASE" '$1==r {print; exit}')
  if [ -z "$ROW" ]; then
    bad "helm list -n $NS shows a release named $RELEASE"
    skip "the release status check (there is no release $RELEASE in $NS)"
  else
    ok "helm list -n $NS shows a release named $RELEASE"
    has "the release $RELEASE has STATUS deployed" "$ROW" "deployed"
  fi

  HSTATUS=$(helm status "$RELEASE" -n "$NS" 2>/dev/null)
  if [ -z "$HSTATUS" ]; then
    bad "helm status $RELEASE -n $NS succeeds"
  else
    ok "helm status $RELEASE -n $NS succeeds"
    has "helm status reports the release as deployed" "$HSTATUS" "deployed"
  fi
fi

# ---- the Deployment in the cluster -------------------------------------------

DEP=$(k -n "$NS" get deploy -l "app.kubernetes.io/instance=$RELEASE" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$DEP" ]; then
  DEP=$(k -n "$NS" get deploy hello-world -o jsonpath='{.metadata.name}' 2>/dev/null)
fi

if [ -z "$DEP" ]; then
  bad "the Deployment the release $RELEASE manages exists in namespace $NS"
  skip "the replica and image checks (there is no Deployment)"
else
  ok "the Deployment the release $RELEASE manages is $DEP"

  REP=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.replicas}' 2>/dev/null)
  eq "the Deployment has 3 replicas" "$REP" "3"

  READY=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  eq "all 3 replicas are ready" "$READY" "3"

  IMG=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
  has "the Deployment runs the image nginx:1.25" "$IMG" "nginx:1.25"
fi

note "helm template renders a chart without touching the cluster, so it is the"
note "safe way to see what a values file produces before you install anything."
note "A values file is a YAML document: 'replicaCount: 3' is a key in it. The"
note "flattened 'replicaCount=3' form belongs to --set on the command line,"
note "and in a file it is a different key that the chart does not read."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}w10 PASSED${X}"; else echo -e "${R}w10 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
