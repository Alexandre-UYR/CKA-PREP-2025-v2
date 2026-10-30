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
RELEASE=stack
CHART=/tmp/cka-lab/charts/stack
VALUES=/tmp/cka-lab/stack-values.yaml

# A small YAML reader, so the values file can be checked without assuming it
# is written in one particular style: block mappings, flow mappings
# (`image: {tag: "2.1.0"}`) and dotted keys all end up as "path|value".
YAML_AWK=$(cat <<'AWKEOF'
function rtrim(s){ sub(/[ \t\r]+$/,"",s); return s }
function ltrim(s){ sub(/^[ \t]+/,"",s); return s }
function unquote(v,   q){
  if (length(v) >= 2) {
    q = substr(v,1,1)
    if ((q == "\"" || q == sprintf("%c",39)) && substr(v,length(v),1) == q) {
      v = substr(v,2,length(v)-2)
    }
  }
  return v
}
function emit(p,v){ print p "|" v }
function splitflow(s, out,   i,c,depth,q,cur,n) {
  depth=0; q=""; cur=""; n=0
  for (i=1;i<=length(s);i++) {
    c=substr(s,i,1)
    if (q!="") { cur=cur c; if (c==q) q=""; continue }
    if (c=="\"" || c==sprintf("%c",39)) { q=c; cur=cur c; continue }
    if (c=="{" || c=="[") { depth++; cur=cur c; continue }
    if (c=="}" || c=="]") { depth--; cur=cur c; continue }
    if (c=="," && depth==0) { n++; out[n]=cur; cur=""; continue }
    cur=cur c
  }
  if (cur!="") { n++; out[n]=cur }
  return n
}
function flow(prefix,key,val,   inner,parts,i,p,j,k,v,full,n) {
  full = (prefix=="" ? key : prefix "." key)
  inner = substr(val,2,length(val)-2)
  n = splitflow(inner,parts)
  for (i=1;i<=n;i++) {
    p=parts[i]; j=index(p,":")
    if (j==0) continue
    k=rtrim(substr(p,1,j-1)); k=ltrim(k)
    v=ltrim(substr(p,j+1))
    if (v ~ /^\{.*\}$/) flow(full,k,v)
    else emit(full "." k, unquote(v))
  }
}
{
  line=$0
  sub(/[ \t]#.*$/,"",line)
  if (line ~ /^[[:space:]]*$/) next
  if (line ~ /^---/) next
  match(line,/^[ ]*/)
  ind=RLENGTH
  body=substr(line,ind+1)
  if (body !~ /^[A-Za-z0-9_.@\/-]+[[:space:]]*:/) next
  idx=index(body,":")
  key=rtrim(substr(body,1,idx-1)); key=ltrim(key)
  val=ltrim(substr(body,idx+1))
  while (sn>0 && sind[sn]>=ind) sn--
  prefix=""
  for (i=1;i<=sn;i++) prefix = prefix (i>1 ? "." : "") skey[i]
  if (val=="") { sn++; sind[sn]=ind; skey[sn]=key; next }
  if (val ~ /^\{.*\}$/) { flow(prefix,key,val); next }
  emit((prefix=="" ? key : prefix "." key), unquote(val))
}
AWKEOF
)

vals_get(){
  # $1 = values file, $2 = dotted path
  awk "$YAML_AWK" "$1" 2>/dev/null \
    | awk -v p="$2" 'index($0, p "|")==1 { print substr($0, length(p)+2); exit }'
}

render_doc(){
  # $1 = kind, $2 = name; the rendered YAML arrives on stdin
  awk -v k="$1" -v n="$2" '
    /^---[[:space:]]*$/ { if (buf ~ k && buf ~ n) print buf; buf=""; next }
    { buf = buf $0 "\n" }
    END { if (buf ~ k && buf ~ n) print buf }
  '
}

check_val(){
  # $1 = what to call the check, $2 = path in the values file, $3 = wanted
  got=$(vals_get "$VALUES" "$2")
  if [ -z "$got" ]; then
    skip "$1 (the values file has no '$2' entry in a form this check can read)"
  else
    eq "$1" "$got" "$3"
  fi
}

echo "== v19: Overriding a subchart's values =="

# ---- the values file ---------------------------------------------------------

if [ -f "$VALUES" ]; then
  ok "the values file $VALUES exists"
else
  bad "the values file $VALUES exists"
  skip "the values file checks (there is no $VALUES)"
fi

if [ -f "$VALUES" ]; then
  if [ -s "$VALUES" ]; then
    ok "the values file $VALUES is not empty"
  else
    bad "the values file $VALUES is not empty"
  fi

  check_val "the values file sets the frontend image tag to 2.1.0" "frontend.image.tag" "2.1.0"
  check_val "the values file sets the frontend replicas to 3" "frontend.replicas" "3"
  check_val "the values file sets the backend image tag to 2.0.5" "backend.image.tag" "2.0.5"
  check_val "the values file sets the backend replicas to 2" "backend.replicas" "2"
  check_val "the values file sets the backend service port to 9090" "backend.service.port" "9090"
fi

# ---- what the chart renders --------------------------------------------------

if ! command -v helm >/dev/null 2>&1; then
  skip "the rendered-chart checks (helm is not on the PATH)"
  skip "the release checks (helm is not on the PATH)"
  echo
  if [ "$FAILS" -eq 0 ]; then echo -e "${G}v19 PASSED${X}"; else echo -e "${R}v19 FAILED ($FAILS checks)${X}"; fi
  exit $(( FAILS > 0 ))
fi

if [ ! -d "$CHART" ]; then
  bad "the chart $CHART is on disk"
  skip "the rendered-chart checks (the chart is missing)"
  skip "the release checks (the chart is missing)"
else
  ok "the chart $CHART is on disk"

  RENDER=$(helm template "$RELEASE" "$CHART" -f "$VALUES" 2>&1)
  if [ $? -ne 0 ] || [ -z "$RENDER" ]; then
    bad "helm template renders the chart with the values file"
    note "helm template said: $(printf '%s' "$RENDER" | head -3 | tr '\n' ' ')"
    skip "the rendered frontend Deployment check"
    skip "the rendered backend Deployment check"
    skip "the rendered backend Service check"
  else
    ok "helm template renders the chart with the values file"

    FE=$(printf '%s\n' "$RENDER" | render_doc "kind: Deployment" "name: frontend")
    if [ -z "$FE" ]; then
      bad "the rendered chart has a frontend Deployment"
    else
      ok "the rendered chart has a frontend Deployment"
      if printf '%s\n' "$FE" | grep -Eq 'replicas:[[:space:]]*3([[:space:]]|$)'; then
        ok "the frontend Deployment has 3 replicas"
      else
        bad "the frontend Deployment has 3 replicas (got: $(printf '%s\n' "$FE" | grep -E 'replicas:' | tr -d ' ' | tr '\n' ' '))"
      fi
      if printf '%s\n' "$FE" | grep -Eq 'image:[[:space:]]*"?[^"]*:2\.1\.0"?'; then
        ok "the frontend Deployment runs the image tag 2.1.0"
      else
        bad "the frontend Deployment runs the image tag 2.1.0 (got: $(printf '%s\n' "$FE" | grep -E 'image:' | tr -d ' ' | tr '\n' ' '))"
      fi
    fi

    BE=$(printf '%s\n' "$RENDER" | render_doc "kind: Deployment" "name: backend")
    if [ -z "$BE" ]; then
      bad "the rendered chart has a backend Deployment"
    else
      ok "the rendered chart has a backend Deployment"
      if printf '%s\n' "$BE" | grep -Eq 'replicas:[[:space:]]*2([[:space:]]|$)'; then
        ok "the backend Deployment has 2 replicas"
      else
        bad "the backend Deployment has 2 replicas (got: $(printf '%s\n' "$BE" | grep -E 'replicas:' | tr -d ' ' | tr '\n' ' '))"
      fi
      if printf '%s\n' "$BE" | grep -Eq 'image:[[:space:]]*"?[^"]*:2\.0\.5"?'; then
        ok "the backend Deployment runs the image tag 2.0.5"
      else
        bad "the backend Deployment runs the image tag 2.0.5 (got: $(printf '%s\n' "$BE" | grep -E 'image:' | tr -d ' ' | tr '\n' ' '))"
      fi
    fi

    BS=$(printf '%s\n' "$RENDER" | render_doc "kind: Service" "name: backend")
    if [ -z "$BS" ]; then
      bad "the rendered chart has a backend Service"
    else
      ok "the rendered chart has a backend Service"
      if printf '%s\n' "$BS" | grep -Eq 'port:[[:space:]]*9090([[:space:]]|$)'; then
        ok "the backend Service is on port 9090"
      else
        bad "the backend Service is on port 9090 (got: $(printf '%s\n' "$BS" | grep -E 'port:' | tr -d ' ' | tr '\n' ' '))"
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
    skip "the helm status report check (helm status returned nothing)"
  else
    ok "helm status $RELEASE -n $NS succeeds"
    has "helm status reports the release as deployed" "$HSTATUS" "deployed"
  fi
fi

note "A subchart's values live under the subchart's own key in the parent's"
note "values file: 'backend:' for a subchart called backend."
note "A --set key that does not start with the subchart's name goes to the"
note "PARENT chart, so '--set replicas=2' never reaches the backend."
note "A dotted key in a values FILE is a literal key - helm does not expand"
note "it - so the values have to be written as nested mappings."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}v19 PASSED${X}"; else echo -e "${R}v19 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
