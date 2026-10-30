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

NS=sec
POD=myuserpod
CM=nginx-conf
CONF_PATH=/etc/nginx/nginx.conf
PORT=8000

echo "== x10: nginx as somebody else =="

if ! exists "Pod $POD exists in namespace $NS" -n "$NS" pod "$POD"; then
  echo; echo -e "${R}x10 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---------------------------------------------------------------------------
# The identity: UID 4242, GID 4242, and nothing else
# ---------------------------------------------------------------------------
RUNAS=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.securityContext.runAsUser}' 2>/dev/null)
if [ -z "$RUNAS" ]; then
  RUNAS=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[*].securityContext.runAsUser}' 2>/dev/null | awk '{print $1}')
  [ -n "$RUNAS" ] && note "runAsUser is set on the container rather than on the Pod"
fi
eq "the Pod runs as UID 4242" "$RUNAS" "4242"

RUNGRP=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.securityContext.runAsGroup}' 2>/dev/null)
if [ -z "$RUNGRP" ]; then
  RUNGRP=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[*].securityContext.runAsGroup}' 2>/dev/null | awk '{print $1}')
fi
FSGRP=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.securityContext.fsGroup}' 2>/dev/null)
if [ -z "$FSGRP" ]; then
  FSGRP=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[*].securityContext.fsGroup}' 2>/dev/null | awk '{print $1}')
fi
if [ "$RUNGRP" = "4242" ]; then
  ok "the Pod runs as GID 4242 (runAsGroup)"
elif [ "$FSGRP" = "4242" ]; then
  ok "the Pod runs with GID 4242 (fsGroup, accepted in place of runAsGroup)"
else
  bad "the Pod runs as GID 4242 (runAsGroup '${RUNGRP:-unset}', fsGroup '${FSGRP:-unset}', want 4242)"
fi

# ---------------------------------------------------------------------------
# It has to be up, and it has to be the container that is ready
# ---------------------------------------------------------------------------
PHASE=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null)
eq "the Pod is Running" "$PHASE" "Running"

READY=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
eq "the container is ready" "$READY" "true"

WAITING=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null)
if [ -n "$WAITING" ]; then
  bad "the container is not waiting on anything (it is waiting on '$WAITING')"
else
  ok "the container is not waiting on anything"
fi

# ---------------------------------------------------------------------------
# The configuration comes from the ConfigMap
# ---------------------------------------------------------------------------
VOL=$(k -n "$NS" get pod "$POD" \
        -o go-template='{{range .spec.volumes}}{{if .configMap}}{{if eq .configMap.name "'"$CM"'"}}{{.name}}{{end}}{{end}}{{end}}' \
        2>/dev/null)
if [ -z "$VOL" ]; then
  bad "the Pod has a volume backed by the ConfigMap $CM"
else
  ok "the Pod has a volume backed by the ConfigMap $CM (volume '$VOL')"
  MP=$(k -n "$NS" get pod "$POD" \
        -o go-template='{{range .spec.containers}}{{range .volumeMounts}}{{if eq .name "'"$VOL"'"}}{{.mountPath}}{{end}}{{end}}{{end}}' \
        2>/dev/null)
  if [ "${MP%/}" = "$CONF_PATH" ]; then
    ok "the ConfigMap is mounted at $CONF_PATH"
  else
    bad "the ConfigMap is mounted at $CONF_PATH (it is mounted at '${MP:-nowhere}')"
  fi
fi

# ---------------------------------------------------------------------------
# Every path the configuration writes to has to be writable
#
# The paths are read out of the ConfigMap rather than assumed, so the check
# follows the configuration the Pod is actually running.
# ---------------------------------------------------------------------------
CONF_DATA=$(k -n "$NS" get cm "$CM" -o jsonpath='{.data.nginx\.conf}' 2>/dev/null)
if [ -z "$CONF_DATA" ]; then
  CONF_DATA=$(k -n "$NS" get cm "$CM" -o jsonpath='{range .data[*]}{.}{"\n"}{end}' 2>/dev/null)
fi

REQ_DIRS=$(printf '%s\n' "$CONF_DATA" | sed -nE \
  -e 's/^[[:space:]]*pid[[:space:]]+(\/[^;]+);.*/\1/p' \
  -e 's/^[[:space:]]*[A-Za-z_]+_temp_path[[:space:]]+(\/[^;]+);.*/\1/p' \
  -e 's/^[[:space:]]*(error_log|access_log)[[:space:]]+(\/[^;]+);.*/\2/p' \
  | while read -r p; do dirname "$p"; done | sort -u)

MOUNTS=$(k -n "$NS" get pod "$POD" \
          -o jsonpath='{range .spec.containers[*].volumeMounts[*]}{.mountPath}{"\n"}{end}' 2>/dev/null)

covered(){
  local want="$1" m
  for m in $MOUNTS; do
    m="${m%/}"
    case "$want" in
      "$m"|"$m"/*) return 0;;
    esac
  done
  return 1
}

if [ -z "$REQ_DIRS" ]; then
  # Nothing could be read out of the ConfigMap: fall back to the paths the
  # stock nginx image uses.
  REQ_DIRS="/var/cache/nginx
/var/run/nginx"
  note "the configuration in $CM could not be parsed, so the standard nginx paths are checked"
fi

for d in $REQ_DIRS; do
  case "$d" in
    /tmp|/var/tmp)
      ok "the nginx configuration writes to $d, which is world-writable in the image";;
    *)
      if covered "$d"; then
        ok "a writable volume is mounted at $d, where the nginx configuration writes"
      else
        bad "a writable volume is mounted at $d, where the nginx configuration writes (nothing is mounted there, so nginx cannot write it as a non-root user)"
      fi;;
  esac
done

# ---------------------------------------------------------------------------
# Live checks
# ---------------------------------------------------------------------------
# A request from inside the Pod to http://localhost:8000 has to come back 200.
# The stock nginx image is a Debian image and has bash, so /dev/tcp does the
# job. If the candidate swapped the image for an alpine one, there is no bash,
# and the request is made from a throwaway Pod instead.
CODE=$(k -n "$NS" exec "$POD" -- bash -c \
  'exec 3<>/dev/tcp/127.0.0.1/'"$PORT"' && printf "GET / HTTP/1.0\r\nHost: localhost\r\n\r\n" >&3 && IFS= read -r line <&3 && printf "%s" "$line"' \
  2>/dev/null | tr -d '\r\n')
STATUS=$(printf '%s' "$CODE" | awk '/^HTTP\//{print $2}' | head -n 1)

if [ -z "$STATUS" ]; then
  note "the request from inside the Pod did not answer - trying the same request from a throwaway Pod"
  IP=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.podIP}' 2>/dev/null)
  PN=x10-probe
  k -n "$NS" delete pod "$PN" --ignore-not-found >/dev/null 2>&1
  k -n "$NS" run "$PN" --image=curlimages/curl --restart=Never --quiet \
      --command -- curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://$IP:$PORT" >/dev/null 2>&1
  i=0
  while [ "$i" -lt 30 ]; do
    PH=$(k -n "$NS" get pod "$PN" -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$PH" = "Succeeded" ] || [ "$PH" = "Failed" ]; then break; fi
    sleep 2
    i=$((i+2))
  done
  STATUS=$(k -n "$NS" logs "$PN" 2>/dev/null | tr -d '\r\n')
  k -n "$NS" delete pod "$PN" --ignore-not-found >/dev/null 2>&1
  if [ "$STATUS" = "200" ]; then
    ok "a request to http://localhost:$PORT returns HTTP 200 (made from a throwaway Pod, because the container has no bash)"
  else
    bad "a request to http://localhost:$PORT returns HTTP 200 (got '${STATUS:-no response}')"
  fi
elif [ "$STATUS" = "200" ]; then
  ok "a request from inside the Pod to http://localhost:$PORT returns HTTP 200"
else
  bad "a request from inside the Pod to http://localhost:$PORT returns HTTP 200 (got '${STATUS:-no response}')"
fi

# And the process really is running as 4242.
IDU=$(k -n "$NS" exec "$POD" -- id -u 2>/dev/null | tr -d '[:space:]')
eq "the process inside the container reports UID 4242" "$IDU" "4242"

note "The stock configuration listens on port 80, so a working answer on 8000"
note "also proves the ConfigMap's configuration is the one nginx is running."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}x10 PASSED${X}"; else echo -e "${R}x10 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
