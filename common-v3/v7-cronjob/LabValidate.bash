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

NS=cron
CJ=reporter
CM=job-config
SA=cron-sa

echo "== v7: Something on a schedule =="

if ! exists "CronJob $CJ exists in namespace $NS" -n "$NS" cronjob "$CJ"; then
  echo; echo -e "${R}v7 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the schedule and the two knobs ----------------------------------------

SCHED=$(k -n "$NS" get cronjob "$CJ" -o jsonpath='{.spec.schedule}' 2>/dev/null)
eq "the CronJob runs on the schedule */2 * * * *" "$SCHED" "*/2 * * * *"

CONC=$(k -n "$NS" get cronjob "$CJ" -o jsonpath='{.spec.concurrencyPolicy}' 2>/dev/null)
eq "concurrencyPolicy is Forbid" "$CONC" "Forbid"

SDS=$(k -n "$NS" get cronjob "$CJ" -o jsonpath='{.spec.startingDeadlineSeconds}' 2>/dev/null)
eq "startingDeadlineSeconds is 60" "$SDS" "60"

# ---- the image and the service account -------------------------------------

IMAGE=$(k -n "$NS" get cronjob "$CJ" \
          -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}' 2>/dev/null)
eq "the job template uses the busybox:1.36 image" "$IMAGE" "busybox:1.36"

SANAME=$(k -n "$NS" get cronjob "$CJ" \
           -o jsonpath='{.spec.jobTemplate.spec.template.spec.serviceAccountName}' 2>/dev/null)
eq "the job template uses the ServiceAccount $SA" "$SANAME" "$SA"

# ---- the ConfigMap value ----------------------------------------------------

MSG=$(k -n "$NS" get configmap "$CM" -o jsonpath='{.data.MSG}' 2>/dev/null)
eq "the ConfigMap $CM still holds MSG" "$MSG" "hello-from-the-configmap"

KEYREF=$(k -n "$NS" get cronjob "$CJ" \
  -o jsonpath='{range .spec.jobTemplate.spec.template.spec.containers[0].env[*]}{.valueFrom.configMapKeyRef.name}{"/"}{.valueFrom.configMapKeyRef.key}{"\n"}{end}' 2>/dev/null)
ENVFROM=$(k -n "$NS" get cronjob "$CJ" \
  -o jsonpath='{range .spec.jobTemplate.spec.template.spec.containers[0].envFrom[*]}{.configMapRef.name}{"\n"}{end}' 2>/dev/null)

if printf '%s\n' "$KEYREF" | grep -qx "$CM/MSG"; then
  ok "the container reads the ConfigMap key MSG from $CM (env valueFrom.configMapKeyRef)"
elif printf '%s\n' "$ENVFROM" | grep -qx "$CM"; then
  ok "the container reads the whole ConfigMap $CM (envFrom configMapRef)"
else
  bad "the container reads the ConfigMap's MSG value (expected env valueFrom.configMapKeyRef name=$CM key=MSG, or envFrom configMapRef $CM)"
fi

# ---- writing under /out ----------------------------------------------------

CMD=$(k -n "$NS" get cronjob "$CJ" \
  -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].command}' 2>/dev/null)
ARGS=$(k -n "$NS" get cronjob "$CJ" \
  -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].args}' 2>/dev/null)

if printf '%s %s' "$CMD" "$ARGS" | grep -Eq '/out(/|$|[^[:alnum:]_])'; then
  ok "the container writes to a path under /out"
else
  bad "the container writes to a path under /out (the command and args do not mention /out)"
fi

MOUNTS=$(k -n "$NS" get cronjob "$CJ" \
  -o jsonpath='{range .spec.jobTemplate.spec.template.spec.containers[0].volumeMounts[*]}{.name}{"|"}{.mountPath}{"\n"}{end}' 2>/dev/null)
VOLUMES=$(k -n "$NS" get cronjob "$CJ" \
  -o jsonpath='{range .spec.jobTemplate.spec.template.spec.volumes[*]}{.name}{"|"}{.emptyDir}{"\n"}{end}' 2>/dev/null)

MOUNT_NAME=""
OLDIFS=$IFS
IFS=$'\n'
for line in $MOUNTS; do
  [ -n "$line" ] || continue
  mname=${line%%|*}
  mpath=${line#*|}
  case "$mpath" in
    /out|/out/*) MOUNT_NAME=$mname;;
  esac
done
IFS=$OLDIFS

if [ -z "$MOUNT_NAME" ]; then
  bad "a volume is mounted at /out (no volumeMount has that path)"
else
  ok "a volume is mounted at /out (volume '$MOUNT_NAME')"
  HAS_EMPTY=0
  OLDIFS=$IFS
  IFS=$'\n'
  for line in $VOLUMES; do
    [ -n "$line" ] || continue
    vname=${line%%|*}
    vkind=${line#*|}
    if [ "$vname" = "$MOUNT_NAME" ] && [ -n "$vkind" ]; then HAS_EMPTY=1; fi
  done
  IFS=$OLDIFS
  if [ "$HAS_EMPTY" -eq 1 ]; then
    ok "the volume mounted at /out is an emptyDir"
  else
    bad "the volume mounted at /out is an emptyDir (volume '$MOUNT_NAME' is not one)"
  fi
fi

# ---- a Job that actually completed -----------------------------------------

JOBS=$(k -n "$NS" get jobs -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -v '^[[:space:]]*$')
if [ -n "$JOBS" ]; then
  ok "a Job exists in namespace $NS"
else
  bad "a Job exists in namespace $NS (none found)"
fi

JOB=""
SUCCEEDED=""
for j in $JOBS; do
  [ -n "$j" ] || continue
  s=$(k -n "$NS" get job "$j" -o jsonpath='{.status.succeeded}' 2>/dev/null)
  if [ -n "$s" ] && [ "$s" -ge 1 ] 2>/dev/null; then
    JOB="$j"
    SUCCEEDED="$s"
    break
  fi
done

if [ -n "$JOB" ]; then
  ok "the Job $JOB completed (status.succeeded = $SUCCEEDED)"
else
  bad "a Job in namespace $NS has status.succeeded of at least 1 (none has completed yet)"
fi

note "*/2 * * * * is every two minutes on the hour, so the CronJob controller may"
note "not create a Job for up to two minutes - which is why the task asks for a"
note "manual trigger with 'kubectl create job --from=cronjob/reporter'."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}v7 PASSED${X}"; else echo -e "${R}v7 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
