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

NS=config
DEP=app

echo "== c4: ConfigMap and Secret as files and as env vars =="

# ---- the ConfigMap ----
exists "ConfigMap app-config exists in namespace $NS" -n "$NS" cm app-config
LV=$(k -n "$NS" get cm app-config -o jsonpath='{.data.LOG_LEVEL}' 2>/dev/null)
eq "the ConfigMap key LOG_LEVEL is debug" "$LV" "debug"

# ---- the Secret ----
exists "Secret app-secret exists in namespace $NS" -n "$NS" secret app-secret
B64=$(k -n "$NS" get secret app-secret -o jsonpath='{.data.DB_PASS}' 2>/dev/null)
DEC=$(printf '%s' "$B64" | base64 -d 2>/dev/null)
eq "the Secret key DB_PASS decodes to s3cret" "$DEC" "s3cret"

# ---- the Deployment ----
exists "Deployment $DEP exists in namespace $NS" -n "$NS" deploy "$DEP"

# ---- the volumes the pod template declares ----
VOLS=$(k -n "$NS" get deploy "$DEP" -o go-template='{{range .spec.template.spec.volumes}}{{.name}}|{{if .configMap}}cm:{{.configMap.name}}{{else if .secret}}sec:{{.secret.secretName}}{{else}}other{{end}}{{"\n"}}{{end}}' 2>/dev/null)
has "the pod template has a volume sourced from the ConfigMap app-config" "$VOLS" "|cm:app-config"
has "the pod template has a volume sourced from the Secret app-secret" "$VOLS" "|sec:app-secret"

CMVOL=$(printf '%s\n' "$VOLS" | grep '|cm:app-config' | cut -d'|' -f1 | head -1)
SECVOL=$(printf '%s\n' "$VOLS" | grep '|sec:app-secret' | cut -d'|' -f1 | head -1)

# ---- the volumeMounts ----
MOUNTS=$(k -n "$NS" get deploy "$DEP" -o go-template='{{range .spec.template.spec.containers}}{{range .volumeMounts}}{{.name}}@{{.mountPath}}:ro={{.readOnly}}{{"\n"}}{{end}}{{end}}' 2>/dev/null)

# mount_ok <volume name> <mount path> -> true or false
mount_ok(){
  if [ -z "$1" ]; then echo false; return 0; fi
  if printf '%s\n' "$MOUNTS" | grep -q -F "$1@$2:"; then echo true; else echo false; fi
}

eq "the app-config volume is mounted at /etc/config" "$(mount_ok "$CMVOL" /etc/config)" "true"
eq "the app-secret volume is mounted at /etc/secret" "$(mount_ok "$SECVOL" /etc/secret)" "true"

ROC=$(printf '%s\n' "$MOUNTS" | grep -F "$CMVOL@/etc/config:" | head -1 | sed 's/.*ro=//')
eq "the /etc/config mount is read-only" "$ROC" "true"

ROS=$(printf '%s\n' "$MOUNTS" | grep -F "$SECVOL@/etc/secret:" | head -1 | sed 's/.*ro=//')
eq "the /etc/secret mount is read-only" "$ROS" "true"

# ---- the environment variables ----
ENVS=$(k -n "$NS" get deploy "$DEP" -o go-template='{{range .spec.template.spec.containers}}{{range .env}}{{.name}}|{{if .valueFrom}}{{if .valueFrom.configMapKeyRef}}cm:{{.valueFrom.configMapKeyRef.name}}/{{.valueFrom.configMapKeyRef.key}}{{else if .valueFrom.secretKeyRef}}sec:{{.valueFrom.secretKeyRef.name}}/{{.valueFrom.secretKeyRef.key}}{{else}}other{{end}}{{else}}literal:{{.value}}{{end}}{{"\n"}}{{end}}{{end}}' 2>/dev/null)

has "the env var LOG_LEVEL comes from the ConfigMap app-config, key LOG_LEVEL" "$ENVS" "LOG_LEVEL|cm:app-config/LOG_LEVEL"
has "the env var DB_PASS comes from the Secret app-secret, key DB_PASS" "$ENVS" "DB_PASS|sec:app-secret/DB_PASS"

LLO=$(printf '%s\n' "$ENVS" | grep '^LOG_LEVEL|' | head -1)
case "$LLO" in
  "")      bad "the env var LOG_LEVEL is not a plain literal value (LOG_LEVEL is not set at all)" ;;
  *"|literal:"*) bad "the env var LOG_LEVEL is not a plain literal value (got '$LLO')" ;;
  *)       ok  "the env var LOG_LEVEL is not a plain literal value" ;;
esac

DBL=$(printf '%s\n' "$ENVS" | grep '^DB_PASS|' | head -1)
case "$DBL" in
  "")      bad "the env var DB_PASS is not a plain literal value (DB_PASS is not set at all)" ;;
  *"|literal:"*) bad "the env var DB_PASS is not a plain literal value (got '$DBL')" ;;
  *)       ok  "the env var DB_PASS is not a plain literal value" ;;
esac

# ---- the pod has to come up for the mounts to mean anything ----
i=0
while [ $i -lt 12 ]; do
  R=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  if [ "$R" = "1" ]; then break; fi
  i=$((i+1)); sleep 3
done
READY=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
eq "the Deployment has 1 ready replica" "$READY" "1"

note "A secretKeyRef has to name the Secret AND the key. Name the Secret but"
note "get the key wrong and the Pod never starts: it sits in"
note "CreateContainerConfigError with 'key \"x\" not found'."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c4 PASSED${X}"; else echo -e "${R}c4 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
