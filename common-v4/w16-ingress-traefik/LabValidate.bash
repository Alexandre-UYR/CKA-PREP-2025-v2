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

NS=web
TRAEFIK_NS=traefik
ING=web
SVC=thirdpage
MARKER=thirdpage-marker
HOST=www.example.com

MADE_PROBE=""

# Finds a pod in the namespace with curl in it, or makes one. Prints the pod
# name on stdout, nothing if it cannot get one.
probe_pod(){
  local name ready
  for name in $(k -n "$NS" get pods -l cka.probe=true -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    ready=$(k -n "$NS" get pod "$name" -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$ready" = "Running" ]; then
      echo "$name"; return 0
    fi
  done

  # None of the pods the setup left behind is usable - make one.
  k -n "$NS" delete pod w16-probe --ignore-not-found >/dev/null 2>&1
  cat <<EOF | k apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: w16-probe
  namespace: $NS
  labels:
    cka.probe: "true"
spec:
  containers:
    - name: probe
      image: curlimages/curl
      command: ["sleep", "3600"]
EOF
  MADE_PROBE="w16-probe"

  local i=0
  while [ "$i" -lt 30 ]; do
    ready=$(k -n "$NS" get pod w16-probe -o jsonpath='{.status.phase}' 2>/dev/null)
    [ "$ready" = "Running" ] && { echo "w16-probe"; return 0; }
    sleep 2
    i=$((i+2))
  done
  return 1
}

echo "== w16: Get a Host header to the right place =="

DEPLOYED=""

# ---- the pre-state ----------------------------------------------------------

exists "Deployment $SVC exists in namespace $NS" -n "$NS" deploy "$SVC"
exists "Service $SVC exists in namespace $NS" -n "$NS" svc "$SVC"

# ---- 1. the Traefik release -------------------------------------------------

exists "namespace $TRAEFIK_NS exists" namespace "$TRAEFIK_NS"

if ! command -v helm >/dev/null 2>&1; then
  skip "the release checks (helm is not on the PATH)"
  skip "the live check (helm is not on the PATH, so there is no Traefik to reach)"
else
  HELMLIST=$(helm list -n "$TRAEFIK_NS" --all 2>/dev/null)
  CHARTFOUND=""
  for r in $(helm list -n "$TRAEFIK_NS" --all -q 2>/dev/null); do
    ST=$(helm status "$r" -n "$TRAEFIK_NS" 2>/dev/null)
    case "$ST" in
      *"STATUS: deployed"*)
        DEPLOYED="$r"
        case "$HELMLIST" in
          *"traefik-"*) CHARTFOUND="yes" ;;
        esac
        break
        ;;
    esac
  done

  if [ -n "$DEPLOYED" ]; then
    ok "there is a helm release in namespace $TRAEFIK_NS with status deployed ($DEPLOYED)"
  else
    bad "there is a helm release in namespace $TRAEFIK_NS with status deployed"
  fi

  if [ -n "$DEPLOYED" ] && [ "$CHARTFOUND" = "yes" ]; then
    ok "the deployed release is the traefik chart"
  elif [ -n "$DEPLOYED" ]; then
    bad "the deployed release is the traefik chart (helm list showed: $(printf '%s' "$HELMLIST" | tr -s ' ' | tr '\n' ' '))"
  else
    skip "the chart check (there is no deployed release to look at)"
  fi
fi

# ---- 2. the Ingress ---------------------------------------------------------

if ! k get ingress "$ING" -n "$NS" >/dev/null 2>&1; then
  bad "Ingress $ING exists in namespace $NS"
  skip "the host check (there is no Ingress $ING)"
  skip "the backend check (there is no Ingress $ING)"
  skip "the ingress class check (there is no Ingress $ING)"
else
  ok "Ingress $ING exists in namespace $NS"

  HOSTS=$(k -n "$NS" get ingress "$ING" -o jsonpath='{range .spec.rules[*]}{.host}{"\n"}{end}' 2>/dev/null | grep -v '^$' | sort -u)
  has "the Ingress has a rule for the host $HOST" "$HOSTS" "$HOST"

  BACKENDS=$(k -n "$NS" get ingress "$ING" \
    -o jsonpath='{range .spec.rules[?(@.host=="'"$HOST"'")]}{range .http.paths[*]}{.backend.service.name}{"\n"}{end}{end}' 2>/dev/null | grep -v '^$' | sort -u)
  has "the rule for $HOST sends traffic to the Service $SVC" "$BACKENDS" "$SVC"

  PORTNUM=$(k -n "$NS" get ingress "$ING" \
    -o jsonpath='{range .spec.rules[?(@.host=="'"$HOST"'")]}{range .http.paths[*]}{.backend.service.port.number}{"\n"}{end}{end}' 2>/dev/null | grep -v '^$' | sort -u)
  PORTNAME=$(k -n "$NS" get ingress "$ING" \
    -o jsonpath='{range .spec.rules[?(@.host=="'"$HOST"'")]}{range .http.paths[*]}{.backend.service.port.name}{"\n"}{end}{end}' 2>/dev/null | grep -v '^$' | sort -u)
  if [ "$PORTNUM" = "80" ]; then
    ok "the backend of the rule for $HOST is on port 80"
  elif [ "$PORTNAME" = "http" ]; then
    ok "the backend of the rule for $HOST names the Service port 'http', which is port 80"
  else
    bad "the backend of the rule for $HOST is on port 80 (got port '${PORTNUM:-none}', name '${PORTNAME:-none}')"
  fi

  CLASS=$(k -n "$NS" get ingress "$ING" -o jsonpath='{.spec.ingressClassName}' 2>/dev/null)
  if [ "$CLASS" = "traefik" ]; then
    ok "the Ingress uses the ingress class traefik"
  elif [ -z "$CLASS" ]; then
    note "the Ingress names no ingress class. It only works if traefik is the default"
    note "ingress class in this cluster - the live check below will tell you."
  else
    bad "the Ingress uses the ingress class traefik (got '$CLASS')"
  fi
fi

# ---- 3. the live check ------------------------------------------------------

if ! command -v helm >/dev/null 2>&1; then
  skip "the live check (helm is not on the PATH, so there is no Traefik to reach)"
elif [ -z "$DEPLOYED" ]; then
  skip "the live check (there is no deployed helm release in namespace $TRAEFIK_NS to reach)"
else
  # The Traefik service: whichever one in the namespace exposes port 80.
  TSVC=""
  for s in $(k -n "$TRAEFIK_NS" get svc -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    P=$(k -n "$TRAEFIK_NS" get svc "$s" -o jsonpath='{.spec.ports[*].port}' 2>/dev/null)
    case " $P " in
      *" 80 "*) TSVC="$s"; break ;;
    esac
  done

  if [ -z "$TSVC" ]; then
    skip "the live check (no service in namespace $TRAEFIK_NS exposes port 80)"
  else
    PROBE=$(probe_pod)
    if [ -z "$PROBE" ]; then
      skip "the live check (no pod with curl could be started in namespace $NS - it needs registry access)"
    else
      # A control request first: if the probe pod cannot reach a Service in its
      # own namespace, the cluster's networking is not usable and the live
      # check cannot say anything about the candidate's work.
      CONTROL=$(k -n "$NS" exec "$PROBE" -- curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://$SVC.$NS.svc.cluster.local/" 2>/dev/null)
      if [ "$CONTROL" != "200" ]; then
        skip "the live check (the probe pod cannot reach the Service $SVC in its own namespace - HTTP '${CONTROL:-no answer}'; the cluster network is not usable for this check)"
      else
        URL="http://$TSVC.$TRAEFIK_NS.svc.cluster.local/"
        OUT=$(k -n "$NS" exec "$PROBE" -- curl -s -w '\n%{http_code}' -H "Host: $HOST" --max-time 15 "$URL" 2>/dev/null)
        CODE=$(printf '%s\n' "$OUT" | tail -n 1)
        BODY=$(printf '%s\n' "$OUT" | sed '$d')

        if [ -z "$CODE" ]; then
          bad "a request from inside the cluster with the Host header $HOST returns HTTP 200 (no answer from $URL)"
          note "The command to run is:"
          note "  kubectl -n $NS exec $PROBE -- curl -s -H 'Host: $HOST' $URL"
        else
          eq "a request from inside the cluster with the Host header $HOST returns HTTP 200" "$CODE" "200"
          has "the response body identifies the third page" "$BODY" "$MARKER"
          has "the response body shows the hostname the request carried" "$BODY" "$HOST"
        fi
      fi
    fi
  fi
fi

if [ -n "$MADE_PROBE" ]; then
  k -n "$NS" delete pod "$MADE_PROBE" --ignore-not-found >/dev/null 2>&1
fi

note "An Ingress routes by HOST as well as by path, so the Host header is what"
note "decides which rule matches - which is why the request has to carry it."
note "The ingress controller has to be installed and reachable for any of it to"
note "work: creating the Ingress object alone changes nothing."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}w16 PASSED${X}"; else echo -e "${R}w16 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
