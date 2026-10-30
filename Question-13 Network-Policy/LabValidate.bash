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
# A check the environment cannot support: prints a line, never counts as a failure.
skip(){ echo "      SKIP  $1"; }
note(){ echo "      NOTE  $1"; }

echo "== Q13 Network Policy =="

BACKEND_URL=http://backend-service.backend.svc.cluster.local

# Run a curl from a throwaway pod in $1 and leave the HTTP status in PROBE_CODE.
# PROBE_OUT keeps the raw output so a failure can say what actually happened.
PROBE_CODE=""
PROBE_OUT=""
probe(){
  local ns="$1" pod="$2" out
  PROBE_CODE=""
  PROBE_OUT=""
  # clear a leftover pod from an interrupted run
  k -n "$ns" delete pod "$pod" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  # note: timeout cannot exec the k() shell function, so call kubectl directly
  if command -v timeout >/dev/null 2>&1; then
    out=$(timeout 180 kubectl -n "$ns" run "$pod" --rm -i --restart=Never --image=curlimages/curl \
            -- curl -s -m 5 -o /dev/null -w "%{http_code}" "$BACKEND_URL" 2>&1)
  else
    out=$(k -n "$ns" run "$pod" --rm -i --restart=Never --image=curlimages/curl \
            -- curl -s -m 5 -o /dev/null -w "%{http_code}" "$BACKEND_URL" 2>&1)
  fi
  PROBE_OUT="$out"
  PROBE_CODE=$(printf '%s\n' "$out" | grep -v '^Warning' | grep -oE '[0-9]{3}' | head -1)
}

# ---- a NetworkPolicy must exist in the backend namespace ----
POLNAME=$(k -n backend get networkpolicy -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}' 2>/dev/null \
          | tr ' ' '\n' | grep -v '^$' | head -1)
if [ -n "$POLNAME" ]; then
  ok "a NetworkPolicy exists in the backend namespace ($POLNAME)"
  PY=$(k -n backend get networkpolicy "$POLNAME" -o yaml 2>/dev/null)
else
  bad "no NetworkPolicy exists in the backend namespace"
  POLNAME=""
  PY=""
fi

if [ -n "$POLNAME" ]; then
  # ---- it must be the least permissive of the three candidates ----
  eq "the applied NetworkPolicy is policy-z, the least permissive of the three" \
    "$POLNAME" "policy-z"

  has "the applied policy selects the backend pods with podSelector app=backend" \
    "$PY" "app: backend"

  has "the applied policy includes the Ingress policy type" \
    "$PY" "- Ingress"

  case "$PY" in
    *ipBlock*)
      bad "the applied policy contains an ipBlock rule - that is policy-y, which also allows 172.16.0.0/16 in, not the least permissive choice";;
    *)
      ok "the applied policy contains no ipBlock rule";;
  esac

  case "$PY" in
    *"{}"*|*"from: []"*)
      bad "the applied policy contains an unrestricted ingress rule (an empty rule) - that is policy-x, which allows all ingress, not the least permissive choice";;
    *)
      ok "the applied policy contains no unrestricted (empty) ingress rule";;
  esac

  # ---- and it must be the file the question handed over ----
  P3=/root/network-policies/network-policy-3.yaml
  if [ -r "$P3" ]; then
    # The trailing {"\n"} keeps the value on its own line, so a stray
    # "created (dry run)" notice can never end up inside the value.
    P3NAME=$(k create --dry-run=client -f "$P3" -o jsonpath='{.metadata.name}{"\n"}' 2>/dev/null | head -1)
    eq "the applied policy is the one described in $P3" "$POLNAME" "$P3NAME"
    P3SPEC=$(k create --dry-run=client -f "$P3" -o jsonpath='{.spec}{"\n"}' 2>/dev/null | head -1)
    APSPEC=$(k -n backend get networkpolicy "$POLNAME" -o jsonpath='{.spec}' 2>/dev/null)
    eq "the applied policy's spec matches $P3" "$APPSPEC" "$P3SPEC"
  else
    skip "$P3 could not be read (it lives under /root - run the setup as root), so the comparison against it was skipped"
  fi
fi

# ---- the frontend namespace has to carry the label policy-z selects on ----
NSLABELS=$(k get ns frontend --show-labels 2>/dev/null)
has "the frontend namespace is labelled name=frontend (policy-z's namespaceSelector needs it)" \
  "$NSLABELS" "name=frontend"

# ---- give the deployments a moment to be ready ----
for _ in $(seq 1 30); do
  BREADY=$(k -n backend get deploy backend-deployment -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [ "${BREADY:-0}" != "0" ] && break
  sleep 2
done

# ---- LIVE test: the frontend namespace must still reach the backend ----
echo
echo "Testing that a pod in the frontend namespace can reach backend-service:80..."
probe frontend np-test
if [ "$PROBE_CODE" = "200" ]; then
  ok "a pod in the frontend namespace reaches backend-service:80 (HTTP 200)"
elif [ -z "$PROBE_CODE" ]; then
  bad "the connectivity test could not be run - the probe pod produced no result: $(printf '%s' "$PROBE_OUT" | tr '\n' ' ' | cut -c1-200)"
else
  bad "a pod in the frontend namespace did NOT reach backend-service:80 (got '$PROBE_CODE', want 200). Either the policy you applied is wrong, OR this cluster's CNI does not enforce NetworkPolicy"
fi

# ---- NEGATIVE test: another namespace must NOT reach the backend ----
echo
echo "Testing that a pod outside the frontend namespace is blocked..."
probe default np-test-neg
if [ -z "$PROBE_CODE" ]; then
  bad "the negative connectivity test could not be run - the probe pod produced no result: $(printf '%s' "$PROBE_OUT" | tr '\n' ' ' | cut -c1-200)"
elif [ "$PROBE_CODE" = "200" ]; then
  bad "a pod outside the frontend namespace STILL reaches backend-service:80 (HTTP 200). Either the policy you applied is wrong, OR this cluster's CNI does not enforce NetworkPolicy"
else
  ok "a pod outside the frontend namespace is blocked from reaching backend-service:80 (got '$PROBE_CODE', not 200)"
fi

# The probe pods use --rm, but clean up explicitly in case one got stuck.
k -n frontend delete pod np-test --ignore-not-found --wait=false >/dev/null 2>&1 || true
k -n default delete pod np-test-neg --ignore-not-found --wait=false >/dev/null 2>&1 || true

note "The negative test only proves something if the CNI enforces NetworkPolicy."
note "A cluster running Flannel, or a CNI with policy enforcement disabled, will"
note "let the traffic through no matter which policy you applied."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}Q13 PASSED${X}"; else echo -e "${R}Q13 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
