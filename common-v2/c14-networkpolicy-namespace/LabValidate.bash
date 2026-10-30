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

NS=netpol
NS_ALLOWED=frontend
NS_BLOCKED=other
POLICY=allow-frontend
TARGET="http://api.netpol.svc.cluster.local"

# Run the curl probe from a namespace and print the HTTP status code it got:
# 200 when the traffic got through, 000 when the connection was dropped.
probe(){
  local ns=$1 name=$2 out="" i=0 phase=""
  k -n "$ns" delete pod "$name" --ignore-not-found --wait=false >/dev/null 2>&1
  if [ -t 0 ]; then
    # Interactive: the canonical one-liner, the pod is removed on exit.
    out=$(k -n "$ns" run "$name" --rm -i --restart=Never --image=curlimages/curl -- \
      curl -s -m 5 -o /dev/null -w "%{http_code}" "$TARGET" 2>/dev/null | tr -d '\r\n')
  else
    # Non-interactive (script, CI): run the pod, read its log, clean it up.
    k -n "$ns" run "$name" --restart=Never --image=curlimages/curl -- \
      curl -s -m 5 -o /dev/null -w "%{http_code}" "$TARGET" >/dev/null 2>&1
    while [ $i -lt 75 ]; do
      phase=$(k -n "$ns" get pod "$name" -o jsonpath='{.status.phase}' 2>/dev/null)
      case "$phase" in Succeeded|Failed) break;; esac
      i=$((i+1)); sleep 2
    done
    out=$(k -n "$ns" logs "$name" 2>/dev/null | tr -d '\r\n')
    k -n "$ns" delete pod "$name" --ignore-not-found --wait=false >/dev/null 2>&1
  fi
  printf '%s' "$out"
}

echo "== c14: Allow ingress from one namespace only =="

if ! exists "NetworkPolicy $POLICY exists in namespace $NS" -n "$NS" netpol "$POLICY"; then
  echo; echo -e "${R}c14 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the policy has to select the api pods ----
PSEL_APP=$(k -n "$NS" get netpol "$POLICY" -o jsonpath='{.spec.podSelector.matchLabels.app}' 2>/dev/null)
PSEL_EXPR=$(k -n "$NS" get netpol "$POLICY" -o jsonpath='{.spec.podSelector.matchExpressions}' 2>/dev/null)
if [ "$PSEL_APP" = "api" ]; then
  ok "the podSelector selects the api pods (matchLabels app=api)"
elif [ -n "$PSEL_EXPR" ] && printf '%s' "$PSEL_EXPR" | grep -q 'app' && printf '%s' "$PSEL_EXPR" | grep -q 'api'; then
  ok "the podSelector selects the api pods (matchExpressions)"
else
  bad "the podSelector selects the api pods (want app=api, got matchLabels '$PSEL_APP' / matchExpressions '$PSEL_EXPR')"
fi

# ---- the policy has to be an ingress policy ----
PTYPES=$(k -n "$NS" get netpol "$POLICY" -o jsonpath='{.spec.policyTypes[*]}' 2>/dev/null)
INGRESS=$(k -n "$NS" get netpol "$POLICY" -o jsonpath='{.spec.ingress}' 2>/dev/null)
case " $PTYPES " in
  *" Ingress "*) ok "policyTypes includes Ingress";;
  *)
    if [ -z "$PTYPES" ] && [ -n "$INGRESS" ]; then
      ok "policyTypes includes Ingress (policyTypes was left unset, so it defaults to [Ingress])"
    else
      bad "policyTypes includes Ingress (got '$PTYPES')"
    fi;;
esac

# ---- walk the ingress rules ----
RULES=$(k -n "$NS" get netpol "$POLICY" -o go-template='{{len .spec.ingress}}' 2>/dev/null)
case "$RULES" in ''|*[!0-9]*) RULES=0;; esac
if [ "$RULES" -gt 0 ]; then
  ok "the policy has at least one ingress rule"
else
  bad "the policy has at least one ingress rule (got none)"
fi

GOOD_RULE=0     # a rule that allows the frontend namespace on TCP 80
OPEN_RULE=0     # a rule that lets every source in
i=0
while [ "$i" -lt "$RULES" ]; do
  # The namespaces this rule's `from` selects.
  NSNAME=$(k -n "$NS" get netpol "$POLICY" -o go-template="{{range (index .spec.ingress ${i}).from}}{{with .namespaceSelector}}{{with .matchLabels}}{{with .name}}{{.}}{{end}}{{end}}{{end}} {{end}}" 2>/dev/null)
  FRONT=0
  case " $NSNAME " in *" frontend "*) FRONT=1;; esac

  # The ports this rule allows, as "port/protocol".
  PORTS=$(k -n "$NS" get netpol "$POLICY" -o go-template="{{range (index .spec.ingress ${i}).ports}}{{.port}}/{{.protocol}} {{end}}" 2>/dev/null)
  PORT80=0
  case " $PORTS " in *" 80/TCP "*) PORT80=1;; esac

  if [ "$FRONT" = "1" ] && [ "$PORT80" = "1" ]; then GOOD_RULE=1; fi

  # A rule with no `from` allows every source.
  HASFROM=$(k -n "$NS" get netpol "$POLICY" -o go-template="{{if (index .spec.ingress ${i}).from}}yes{{else}}no{{end}}" 2>/dev/null)
  if [ "$HASFROM" != "yes" ]; then OPEN_RULE=1; fi

  i=$((i+1))
done

if [ "$GOOD_RULE" = "1" ]; then
  ok "an ingress rule allows the frontend namespace (namespaceSelector name=frontend)"
else
  bad "an ingress rule allows the frontend namespace (namespaceSelector with matchLabels name: frontend)"
fi

if [ "$GOOD_RULE" = "1" ]; then
  ok "that rule restricts the traffic to TCP port 80"
else
  bad "that rule restricts the traffic to TCP port 80 (want ports: [{protocol: TCP, port: 80}])"
fi

if [ "$OPEN_RULE" = "0" ]; then
  ok "no rule allows every source (no empty 'from' and no empty ingress rule)"
else
  bad "no rule allows every source (found an ingress rule with no 'from' - it allows every source, which defeats the policy)"
fi

IPBLOCK=$(k -n "$NS" get netpol "$POLICY" -o go-template="{{range .spec.ingress}}{{range .from}}{{with .ipBlock}}yes{{end}}{{end}}{{end}}" 2>/dev/null)
if [ -z "$IPBLOCK" ]; then
  ok "the policy does not use an ipBlock"
else
  bad "the policy does not use an ipBlock (an ipBlock selects by CIDR, not by namespace)"
fi

# ---- the api pods have to be up before a traffic test means anything ----
i=0
READY=""
while [ $i -lt 30 ]; do
  READY=$(k -n "$NS" get deploy api -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  case "$READY" in ''|*[!0-9]*) READY=0;; esac
  [ "$READY" -ge 1 ] && break
  i=$((i+1)); sleep 3
done
if [ "${READY:-0}" -ge 1 ]; then
  ok "the api Deployment has at least 1 ready replica"
else
  bad "the api Deployment has at least 1 ready replica (the pre-state is not up - this is not the candidate's answer)"
fi

# ---- live test: the allowed namespace ----
CODE_OK=$(probe "$NS_ALLOWED" probe-frontend)
if [ "$CODE_OK" = "200" ]; then
  ok "a pod in namespace $NS_ALLOWED reaches $TARGET (HTTP 200)"
else
  bad "a pod in namespace $NS_ALLOWED reaches $TARGET (HTTP 200) (got '${CODE_OK:-<no output>}')"
fi

# ---- live test: the denied namespace ----
CODE_NO=$(probe "$NS_BLOCKED" probe-other)
if [ -z "$CODE_NO" ]; then
  bad "a pod in namespace $NS_BLOCKED cannot reach $TARGET (the probe produced no output - the probe pod could not run, so the test proves nothing)"
elif [ "$CODE_NO" = "200" ]; then
  bad "a pod in namespace $NS_BLOCKED cannot reach $TARGET (got HTTP 200) - EITHER the policy is wrong, OR this cluster's CNI does not enforce NetworkPolicy"
else
  ok "a pod in namespace $NS_BLOCKED cannot reach $TARGET (got '$CODE_NO', blocked)"
fi

note "A NetworkPolicy that selects a pod isolates it for ingress: whatever is not"
note "explicitly allowed is dropped, so one narrow rule denies everything else."
note "NetworkPolicy is only enforced if the CNI implements it. On a cluster whose"
note "CNI ignores policies, the denied probe still answers 200 - that is the"
note "cluster's limitation, not the candidate's mistake."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c14 PASSED${X}"; else echo -e "${R}c14 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
