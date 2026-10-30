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

NS=sidecar
DEP=app

echo "== c2: Sidecar sharing an emptyDir =="

if ! exists "Deployment $DEP exists in namespace $NS" -n "$NS" deploy "$DEP"; then
  echo; echo -e "${R}c2 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the sidecar container ----
NAMES=$(k -n "$NS" get deploy "$DEP" -o go-template='{{range .spec.template.spec.containers}}{{.name}} {{end}}' 2>/dev/null)
NC=$(printf '%s' "$NAMES" | wc -w | tr -d ' ')
eq "the Deployment has exactly 2 containers" "$NC" "2"

has "a container named sidecar exists" " $NAMES " " sidecar "

SIMG=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.template.spec.containers[?(@.name=="sidecar")].image}' 2>/dev/null)
eq "the sidecar container uses the image busybox:stable" "$SIMG" "busybox:stable"

SCMD=$(k -n "$NS" get deploy "$DEP" -o go-template='{{range .spec.template.spec.containers}}{{if eq .name "sidecar"}}{{range .command}}{{.}} {{end}}{{range .args}}{{.}} {{end}}{{end}}{{end}}' 2>/dev/null)
has "the sidecar command writes to app.log" "$SCMD" "app.log"

# ---- the shared volume ----
VNAMES=$(k -n "$NS" get deploy "$DEP" -o go-template='{{range .spec.template.spec.volumes}}{{.name}} {{end}}' 2>/dev/null)
has "the pod template has a volume named logs" " $VNAMES " " logs "

# The source field of the volume tells us its type: emptyDir, hostPath,
# configMap, secret, ... Note that an empty map is falsy in a Go template, so
# "if .emptyDir" would be false for the emptyDir: {} that Kubernetes stores.
VTYPE=$(k -n "$NS" get deploy "$DEP" -o go-template='{{range .spec.template.spec.volumes}}{{if eq .name "logs"}}{{range $k, $v := .}}{{if ne $k "name"}}{{$k}} {{end}}{{end}}{{end}}{{end}}' 2>/dev/null | tr -d ' \n')
eq "the volume 'logs' is of type emptyDir" "$VTYPE" "emptyDir"

# ---- both containers must mount it at the same path ----
for c in $NAMES; do
  MP=$(k -n "$NS" get deploy "$DEP" -o jsonpath="{.spec.template.spec.containers[?(@.name==\"$c\")].volumeMounts[?(@.name==\"logs\")].mountPath}" 2>/dev/null)
  eq "the $c container mounts the volume 'logs' at /var/log" "$MP" "/var/log"
done

# ---- the rollout has to finish before the live check means anything ----
i=0
while [ $i -lt 12 ]; do
  R=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  if [ "$R" = "1" ]; then break; fi
  i=$((i+1)); sleep 3
done
READY=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
eq "the Deployment has 1 ready replica" "$READY" "1"

# ---- live check: the shared file really is visible from the sidecar ----
# The form the task names is tried first. During a rollout the old pod can
# still be around, and it has no sidecar container, so each pod that does
# have one is tried as well.
LIVE=0
i=0
while [ $i -lt 8 ]; do
  if k -n "$NS" exec deploy/"$DEP" -c sidecar -- ls -l /var/log/app.log >/dev/null 2>&1; then
    LIVE=1; break
  fi
  for p in $(k -n "$NS" get pods -l app=app -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    CN=$(k -n "$NS" get pod "$p" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null)
    case " $CN " in
      *" sidecar "*) ;;
      *) continue ;;
    esac
    if k -n "$NS" exec "$p" -c sidecar -- ls -l /var/log/app.log >/dev/null 2>&1; then
      LIVE=1; break
    fi
  done
  if [ "$LIVE" = "1" ]; then break; fi
  i=$((i+1)); sleep 3
done
if [ "$LIVE" = "1" ]; then
  ok "the shared file /var/log/app.log exists inside the sidecar container"
else
  bad "the shared file /var/log/app.log exists inside the sidecar container (live exec failed: kubectl -n $NS exec deploy/$DEP -c sidecar -- ls -l /var/log/app.log)"
fi

note "A Pod's containers share a lifecycle: if one of them exits, the Pod is"
note "restarted as a whole. That is why the sidecar's loop has to keep running."
note "The two containers must agree on the volume NAME as well as the path - a"
note "volumeMount refers to a volume by name, not by its type."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}c2 PASSED${X}"; else echo -e "${R}c2 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
