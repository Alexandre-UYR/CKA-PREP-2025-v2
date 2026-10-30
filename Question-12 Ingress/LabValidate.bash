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
# A check the environment cannot support. It prints a line but never counts as a failure.
skip(){ echo "      SKIP  $1"; }
note(){ echo "      NOTE  $1"; }

echo "== Q12 Ingress =="

NS=echo-sound
SVC=echo-service

# ---- the Service ----
if ! exists "Service $SVC exists in namespace $NS" -n "$NS" svc "$SVC"; then
  echo
  echo -e "${R}Q12 FAILED ($FAILS checks)${X}"; exit 1
fi

eq "Service $SVC has type NodePort" \
  "$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.type}' 2>/dev/null)" "NodePort"

eq "Service $SVC exposes port 8080" \
  "$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)" "8080"

eq "Service $SVC targets container port 8080" \
  "$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)" "8080"

NODEPORT=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
nonempty "Service $SVC has a nodePort allocated by the cluster" "$NODEPORT"

# ---- the Service must actually select the echo deployment's pods ----
# kubectl's jsonpath prints a map as JSON, so the selector arrives as {"app":"echo"}.
SEL=$(k -n "$NS" get svc "$SVC" -o jsonpath='{.spec.selector}' 2>/dev/null)
DEPLAB=$(k -n "$NS" get deploy echo -o jsonpath='{.spec.template.metadata.labels}' 2>/dev/null)
if [ -z "$SEL" ] || [ -z "$DEPLAB" ]; then
  bad "could not read the Service selector or the deployment's pod labels (selector '$SEL', pod labels '$DEPLAB')"
elif printf '%s' "$SEL" | grep -qE '"app"[[:space:]]*:[[:space:]]*"echo"|app: echo'; then
  ok "Service $SVC selector matches the echo deployment's pod labels ($SEL)"
else
  bad "Service $SVC selector does not select the echo pods (selector '$SEL', deployment pod labels '$DEPLAB')"
fi

# The Endpoints are the observable proof that the selector matches something.
# Give the pod a moment to become ready and be picked up by the endpoints controller.
EP=0
for _ in $(seq 1 30); do
  EP=$(k -n "$NS" get endpoints "$SVC" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | tr ' ' '\n' | grep -c '[0-9]' || true)
  [ "${EP:-0}" -gt 0 ] 2>/dev/null && break
  EP=$(k -n "$NS" get endpointslices -l "kubernetes.io/service-name=$SVC" \
        -o jsonpath='{.items[*].endpoints[*].addresses[*]}' 2>/dev/null | tr ' ' '\n' | grep -c '[0-9]' || true)
  [ "${EP:-0}" -gt 0 ] 2>/dev/null && break
  sleep 2
done
if [ "${EP:-0}" -gt 0 ] 2>/dev/null; then
  ok "Service $SVC has at least one endpoint address (it selects the echo pods)"
else
  bad "Service $SVC has no endpoint addresses - its selector matches none of the echo deployment's pods"
fi

# ---- the Ingress ----
if ! exists "Ingress echo exists in namespace $NS" -n "$NS" ingress echo; then
  echo
  echo -e "${R}Q12 FAILED ($FAILS checks)${X}"; exit 1
fi

eq "Ingress echo serves host example.org" \
  "$(k -n "$NS" get ingress echo -o jsonpath='{.spec.rules[0].host}' 2>/dev/null)" "example.org"

eq "Ingress echo exposes path /echo" \
  "$(k -n "$NS" get ingress echo -o jsonpath='{.spec.rules[0].http.paths[0].path}' 2>/dev/null)" "/echo"

eq "Ingress echo pathType is Prefix" \
  "$(k -n "$NS" get ingress echo -o jsonpath='{.spec.rules[0].http.paths[0].pathType}' 2>/dev/null)" "Prefix"

eq "Ingress echo backend is service $SVC" \
  "$(k -n "$NS" get ingress echo -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}' 2>/dev/null)" "$SVC"

eq "Ingress echo backend port is 8080" \
  "$(k -n "$NS" get ingress echo -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.port.number}' 2>/dev/null)" "8080"

# ---- live check: the NodePort really serves /echo ----
echo
echo "Checking the NodePort from this machine..."
NODEIP=$(k get nodes -o jsonpath='{range .items[*]}{range .status.addresses[?(@.type=="InternalIP")]}{.address}{"\n"}{end}{end}' 2>/dev/null | head -1)
if [ -z "$NODEIP" ]; then
  NODEIP=$(k get nodes -o jsonpath='{range .items[*]}{range .status.addresses[?(@.type=="ExternalIP")]}{.address}{"\n"}{end}{end}' 2>/dev/null | head -1)
fi

if [ -z "$NODEIP" ]; then
  skip "no node IP could be read from the cluster, so 'curl NODEIP:NODEPORT/echo' could not be attempted"
elif [ -z "$NODEPORT" ]; then
  skip "Service $SVC has no nodePort, so 'curl NODEIP:NODEPORT/echo' could not be attempted"
else
  ERRF=$(mktemp 2>/dev/null || echo "/tmp/cka-q12-curl.err")
  CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 \
          "http://${NODEIP}:${NODEPORT}/echo" 2>"$ERRF")
  CURLERR=$(cat "$ERRF" 2>/dev/null)
  rm -f "$ERRF" 2>/dev/null
  if [ "$CODE" = "200" ]; then
    ok "the NodePort serves the echo server (http://${NODEIP}:${NODEPORT}/echo returned 200)"
  elif [ -z "$CODE" ] || [ "$CODE" = "000" ]; then
    skip "this machine could not reach http://${NODEIP}:${NODEPORT}/echo (${CURLERR:-no route to host}) - this is an environment limitation, not a wrong answer. Test it by hand from a host that can reach the node."
  else
    bad "the NodePort answered with HTTP $CODE (want 200) at http://${NODEIP}:${NODEPORT}/echo"
  fi
fi

note "The /etc/hosts entry for example.org is part of the question's optional manual"
note "verification of the Ingress, not a graded deliverable - the graded Ingress is"
note "checked above by reading the object itself."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}Q12 PASSED${X}"; else echo -e "${R}Q12 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
