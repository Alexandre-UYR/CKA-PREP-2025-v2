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

NS=secrets
DEP=secret
SEC=app-secret

echo "== w13: The same Secret, two ways =="

# ---- the pre-state is still there -------------------------------------------
exists "Secret $SEC exists in namespace $NS" -n "$NS" secret "$SEC"

if ! exists "Deployment $DEP exists in namespace $NS" -n "$NS" deploy "$DEP"; then
  echo; echo -e "${R}w13 FAILED ($FAILS checks)${X}"; exit 1
fi

READY=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
eq "the deployment has 1 ready replica" "$READY" "1"

# ---------------------------------------------------------------------------
# The environment variables: either envFrom, or env entries with secretKeyRef
# ---------------------------------------------------------------------------

ENVFROM=$(k -n "$NS" get deploy "$DEP" \
  -o jsonpath='{.spec.template.spec.containers[0].envFrom[?(@.secretRef.name=="app-secret")].secretRef.name}' 2>/dev/null)

ENVKEYS=$(k -n "$NS" get deploy "$DEP" \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.valueFrom.secretKeyRef.name=="app-secret")].valueFrom.secretKeyRef.key}' 2>/dev/null)
ENVNAMES=$(k -n "$NS" get deploy "$DEP" \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.valueFrom.secretKeyRef.name=="app-secret")].name}' 2>/dev/null)

if [ "$ENVFROM" = "$SEC" ]; then
  ok "the container sources the Secret with envFrom (secretRef $SEC)"
  note "envFrom imports every key of the Secret, and the environment variable"
  note "names are the KEY names - there is no way to rename them with envFrom."
elif printf '%s' "$ENVKEYS" | grep -q 'username' && printf '%s' "$ENVKEYS" | grep -q 'password'; then
  ok "the container sources the Secret with two secretKeyRef env entries (keys: $ENVKEYS)"
  if printf '%s' "$ENVNAMES" | grep -q 'username' && printf '%s' "$ENVNAMES" | grep -q 'password'; then
    ok "the env variables are named username and password"
  else
    bad "the env variables are named username and password (got '$ENVNAMES')"
  fi
else
  bad "the container sources the Secret's keys as environment variables (envFrom='$ENVFROM', secretKeyRef keys='$ENVKEYS')"
fi

# The values must come from the Secret, not from a literal in the manifest.
HARDCODED=$(k -n "$NS" get deploy "$DEP" \
  -o jsonpath='{.spec.template.spec.containers[0].env[*].value}' 2>/dev/null)
case "$HARDCODED" in
  *admin*|*s3cr3t*)
    bad "the environment variables are not hard-coded literals (found '$HARDCODED')"
    ;;
  *)
    ok "the environment variables are not hard-coded literals"
    ;;
esac

# ---------------------------------------------------------------------------
# The mounted volume
# ---------------------------------------------------------------------------

VOLSEC=$(k -n "$NS" get deploy "$DEP" \
  -o jsonpath='{.spec.template.spec.volumes[?(@.secret)].secret.secretName}' 2>/dev/null)
VOLPROJ=$(k -n "$NS" get deploy "$DEP" \
  -o jsonpath='{.spec.template.spec.volumes[?(@.projected)].projected.sources[?(@.secret)].secret.name}' 2>/dev/null)
MOUNTS=$(k -n "$NS" get deploy "$DEP" \
  -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.mountPath=="/etc/secret")].mountPath}' 2>/dev/null)

if [ -z "$VOLSEC" ] && [ -z "$VOLPROJ" ]; then
  bad "the Secret $SEC is mounted as a volume"
else
  has "the mounted volume comes from Secret $SEC" "$VOLSEC$VOLPROJ" "$SEC"
fi
has "the container mounts a volume at /etc/secret" "$MOUNTS" "/etc/secret"

# ---------------------------------------------------------------------------
# The live checks: what the pod actually sees
# ---------------------------------------------------------------------------

SEL=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.selector.matchLabels}' 2>/dev/null | tr ':' '=')
POD=$(k -n "$NS" get pods -l "$SEL" --field-selector=status.phase=Running \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$POD" ]; then
  POD=$(k -n "$NS" get pods --field-selector=status.phase=Running \
          -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep "^$DEP-" | head -1)
fi

if [ -z "$POD" ]; then
  bad "a Running pod exists for the $DEP deployment"
  skip "the environment variable checks"
  skip "the mounted file checks"
else
  ok "the pod is $POD"

  echo "Checking the environment variables from inside the pod..."
  ENVU=$(k -n "$NS" exec "$POD" -- printenv username 2>/dev/null | tr -d '\r\n')
  eq "printenv username inside the pod gives admin" "$ENVU" "admin"

  ENVP=$(k -n "$NS" exec "$POD" -- printenv password 2>/dev/null | tr -d '\r\n')
  eq "printenv password inside the pod gives s3cr3t" "$ENVP" "s3cr3t"

  echo "Checking the mounted files from inside the pod..."
  FILEU=$(k -n "$NS" exec "$POD" -- cat /etc/secret/username 2>/dev/null | tr -d '\r\n')
  if [ "$FILEU" = "admin" ]; then
    ok "/etc/secret/username inside the pod holds admin"
  else
    bad "/etc/secret/username inside the pod holds admin (got '$FILEU')"
  fi

  FILEP=$(k -n "$NS" exec "$POD" -- cat /etc/secret/password 2>/dev/null | tr -d '\r\n')
  if [ "$FILEP" = "s3cr3t" ]; then
    ok "/etc/secret/password inside the pod holds s3cr3t"
  else
    bad "/etc/secret/password inside the pod holds s3cr3t (got '$FILEP')"
  fi
fi

note "A Secret mounted as a volume appears as one FILE PER KEY, named after the"
note "key, and the kubelet decodes the base64 for you: /etc/secret/username"
note "holds admin, not YWRtaW4=."
note "envFrom imports every key of the Secret, so the environment variable"
note "names are the KEY names - there is no way to rename them with envFrom."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}w13 PASSED${X}"; else echo -e "${R}w13 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
