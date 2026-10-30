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

NS=dodgy
SVC=dodgy-svc
LABDIR=/tmp/cka-lab
MANIFEST="$LABDIR/dodgy.yaml"

echo "== x9: The manifest that does not do what it says =="

if ! exists "namespace $NS exists" namespace "$NS"; then
  echo; echo -e "${R}x9 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---------------------------------------------------------------------------
# Read the manifest off disk. It is the file the candidate was told to fix,
# so it is the file that is graded - not whatever happens to be in the
# cluster.
# ---------------------------------------------------------------------------
if [ ! -s "$MANIFEST" ]; then
  bad "the manifest $MANIFEST exists and can be read (it is missing or empty)"
  echo; echo -e "${R}x9 FAILED ($FAILS checks)${X}"; exit 1
fi
ok "the manifest $MANIFEST exists and can be read"

mf(){
  # Prints a jsonpath expression out of the manifest, without touching the
  # cluster. If the file cannot be parsed, nothing is printed.
  k create --dry-run=client -f "$MANIFEST" -o "jsonpath=$1" 2>/dev/null | head -1
}

mf_map(){
  # Prints a label map out of the manifest as "k=v k=v".
  k create --dry-run=client -f "$MANIFEST" -o "go-template=$1" 2>/dev/null | head -1
}

norm_map(){
  # Turns a label map (app=dodgy-app) into a sorted list of k=v.
  printf '%s' "$1" | tr ' ' '\n' | sed 's/"//g' | grep '=' | sort | tr '\n' ' '
}

SEL_RAW=$(mf_map '{{range $k, $v := .spec.selector.matchLabels}}{{$k}}={{$v}} {{end}}')
LAB_RAW=$(mf_map '{{range $k, $v := .spec.template.metadata.labels}}{{$k}}={{$v}} {{end}}')
CPORT=$(mf '{.spec.template.spec.containers[0].ports[0].containerPort}')
DEP_NAME=$(mf '{.metadata.name}')

# The replicas have to be read out of the FILE, not out of the decoded
# object: the API server defaults a missing spec.replicas to 1, so the
# decoded object would show a number even when the manifest never said one.
RAW_REPLICAS=$(grep -v '^[[:space:]]*#' "$MANIFEST" \
  | grep -E '^[[:space:]]+replicas[[:space:]]*:' | head -1 \
  | sed 's/.*replicas[[:space:]]*:[[:space:]]*//' | tr -d '"'"'"' \r')

if [ -z "$SEL_RAW" ] && [ -z "$LAB_RAW" ] && [ -z "$CPORT" ]; then
  bad "the manifest can be parsed (kubectl could not read a Deployment out of it)"
  echo; echo -e "${R}x9 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- 1. the selector has to match the pod template's labels ----
SEL=$(norm_map "$SEL_RAW")
LAB=$(norm_map "$LAB_RAW")

if [ -z "$SEL" ]; then
  bad "the manifest's selector matches its pod template's labels (the selector is empty)"
else
  SELBAD=0
  for entry in $SEL; do
    KEY=${entry%%=*}
    VAL=${entry#*=}
    case " $LAB " in
      *" $KEY=$VAL "*) ok "the manifest's selector '$KEY=$VAL' matches the pod template's labels" ;;
      *) bad "the manifest's selector '$KEY=$VAL' matches the pod template's labels (the template is labelled '$LAB')"; SELBAD=1 ;;
    esac
  done
  if [ "$SELBAD" = "0" ]; then
    ok "every label in the selector is present in the pod template's labels"
  fi
fi

# ---- 2. the container port has to match the Service's targetPort ----
SVC_TPORT=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)
eq "the Service $SVC still targets port 8080" "$SVC_TPORT" "8080"
eq "the manifest's container port is 8080" "$CPORT" "8080"

# ---- 3. the manifest has to say how many replicas it wants ----
case "$RAW_REPLICAS" in
  ''|*[!0-9]*)
    bad "the manifest declares a positive number of replicas (got '$RAW_REPLICAS')" ;;
  *)
    if [ "$RAW_REPLICAS" -gt 0 ]; then
      ok "the manifest declares $RAW_REPLICAS replica(s)"
    else
      bad "the manifest declares a positive number of replicas (got '$RAW_REPLICAS')"
    fi ;;
esac

# ---- 4. and it has to have been applied ----
if [ -z "$DEP_NAME" ]; then DEP_NAME="dodgy-app"; fi
if exists "Deployment $DEP_NAME exists in namespace $NS" -n "$NS" deploy "$DEP_NAME"; then
  READY=$(k -n "$NS" get deploy "$DEP_NAME" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  case "$READY" in ''|*[!0-9]*) READY=0;; esac
  if [ "${READY:-0}" -ge 1 ]; then
    ok "the Deployment has $READY ready replica(s)"
  else
    bad "the Deployment has at least 1 ready replica (got '${READY:-0}' - 'kubectl -n $NS describe deploy $DEP_NAME' says why)"
  fi

  LIVE_PORT=$(k -n "$NS" get deploy "$DEP_NAME" -o jsonpath='{.spec.template.spec.containers[0].ports[0].containerPort}' 2>/dev/null)
  eq "the applied Deployment's container port is 8080" "$LIVE_PORT" "8080"

  LIVE_SEL=$(k -n "$NS" get deploy "$DEP_NAME" -o go-template='{{range $k, $v := .spec.selector.matchLabels}}{{$k}}={{$v}} {{end}}' 2>/dev/null)
  LIVE_LAB=$(k -n "$NS" get deploy "$DEP_NAME" -o go-template='{{range $k, $v := .spec.template.metadata.labels}}{{$k}}={{$v}} {{end}}' 2>/dev/null)
  LIVE_SEL=$(norm_map "$LIVE_SEL")
  LIVE_LAB=$(norm_map "$LIVE_LAB")
  if [ -n "$LIVE_SEL" ]; then
    SELBAD=0
    for entry in $LIVE_SEL; do
      KEY=${entry%%=*}
      VAL=${entry#*=}
      case " $LIVE_LAB " in
        *" $KEY=$VAL "*) ;;
        *) SELBAD=1 ;;
      esac
    done
    if [ "$SELBAD" = "0" ]; then
      ok "the applied Deployment's selector matches its pod template's labels"
    else
      bad "the applied Deployment's selector matches its pod template's labels (selector '$LIVE_SEL', template labels '$LIVE_LAB')"
    fi
  fi
else
  bad "Deployment $DEP_NAME exists in namespace $NS"
fi

# ---- 5. and the Service has to have found it ----
EP=0
for i in $(seq 1 15); do
  EP=$(k -n "$NS" get endpoints "$SVC" -o jsonpath='{range .subsets[*].addresses[*]}{.ip}{"\n"}{end}' 2>/dev/null | grep -c '[0-9]' || true)
  if [ "${EP:-0}" -ge 1 ] 2>/dev/null; then break; fi
  sleep 2
done
if [ "${EP:-0}" -ge 1 ] 2>/dev/null; then
  ok "the Service $SVC has endpoints ($EP endpoint address(es))"
else
  bad "the Service $SVC has endpoints (got ${EP:-0}, want at least 1)"
fi

note "A Service whose targetPort matches none of the pod's container ports"
note "resolves to no endpoints, and nothing errors - the Endpoints object is"
note "simply empty."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}x9 PASSED${X}"; else echo -e "${R}x9 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
