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

NS=rot
DEP=app
SEC=app-secret

echo "== v11: Which one sees the new value? =="

if ! exists "Secret $SEC exists in namespace $NS" -n "$NS" secret "$SEC"; then
  echo; echo -e "${R}v11 FAILED ($FAILS checks)${X}"; exit 1
fi
if ! exists "Deployment $DEP exists in namespace $NS" -n "$NS" deploy "$DEP"; then
  echo; echo -e "${R}v11 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the Secret really is rotated ----
SECB64=$(k -n "$NS" get secret "$SEC" -o jsonpath='{.data.TOKEN}' 2>/dev/null)
SECVAL=$(printf '%s' "$SECB64" | base64 -d 2>/dev/null || printf '%s' "$SECB64" | base64 -D 2>/dev/null)
eq "the Secret $SEC holds TOKEN=new-value" "$SECVAL" "new-value"

# ---- the Deployment is still wired to the Secret, both ways ----
ENVSRC=$(k -n "$NS" get deploy "$DEP" \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="TOKEN")].valueFrom.secretKeyRef.name}' 2>/dev/null)
ENVKEY=$(k -n "$NS" get deploy "$DEP" \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="TOKEN")].valueFrom.secretKeyRef.key}' 2>/dev/null)
ENVLIT=$(k -n "$NS" get deploy "$DEP" \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="TOKEN")].value}' 2>/dev/null)
eq "the TOKEN env var is sourced from secretKeyRef $SEC" "$ENVSRC" "$SEC"
eq "the secretKeyRef reads the key TOKEN" "$ENVKEY" "TOKEN"
if [ -n "$ENVLIT" ]; then
  bad "the TOKEN env var is not a hard-coded literal (found value '$ENVLIT')"
else
  ok "the TOKEN env var is not a hard-coded literal"
fi

VOLSEC=$(k -n "$NS" get deploy "$DEP" \
  -o jsonpath='{.spec.template.spec.volumes[?(@.secret)].secret.secretName}' 2>/dev/null)
MOUNTS=$(k -n "$NS" get deploy "$DEP" \
  -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.mountPath=="/etc/secret")].mountPath}' 2>/dev/null)
has "the mounted volume comes from Secret $SEC" "$VOLSEC" "$SEC"
has "the container still mounts a volume at /etc/secret" "$MOUNTS" "/etc/secret"

# ---- the pod ----
POD=$(k -n "$NS" get pods -l "app=$DEP" --field-selector=status.phase=Running \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$POD" ]; then
  bad "a Running pod exists for the $DEP deployment"
  echo; echo -e "${R}v11 FAILED ($FAILS checks)${X}"; exit 1
fi
ok "the pod is $POD"

READY=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
eq "the deployment has 1 ready replica" "$READY" "1"

CONREADY=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
eq "the container is ready" "$CONREADY" "true"

# ---- the mounted file, with the kubelet's refresh window ----
echo "Checking the mounted file (the kubelet refreshes it in place, which can take about two minutes)..."
FILEVAL=""
i=0
while [ "$i" -lt 36 ]; do
  POD=$(k -n "$NS" get pods -l "app=$DEP" --field-selector=status.phase=Running \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -n "$POD" ]; then
    FILEVAL=$(k -n "$NS" exec "$POD" -- cat /etc/secret/TOKEN 2>/dev/null | tr -d '\r\n')
  fi
  [ "$FILEVAL" = "new-value" ] && break
  sleep 5
  i=$((i+5))
done
eq "the mounted file /etc/secret/TOKEN holds new-value" "$FILEVAL" "new-value"

# ---- the environment variable inside the container ----
ENVVAL=$(k -n "$NS" exec "$POD" -- printenv TOKEN 2>/dev/null | tr -d '\r\n')
if [ "$ENVVAL" = "new-value" ] || [ "$ENVVAL" = "old-value" ]; then
  ok "the container's TOKEN environment variable holds a value from the Secret ($ENVVAL)"
else
  bad "the container's TOKEN environment variable holds '$ENVVAL' (expected 'old-value' or 'new-value')"
fi

note "An environment variable is read once, when the container starts. The pod has not"
note "restarted, so TOKEN still holds the value the Secret had at start-up."
note "A Secret mounted as a volume is a projection: the kubelet rewrites the files in"
note "place when the Secret changes, so the file followed the rotation on its own."
note "subPath mounts are the exception - they are never refreshed."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}v11 PASSED${X}"; else echo -e "${R}v11 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
