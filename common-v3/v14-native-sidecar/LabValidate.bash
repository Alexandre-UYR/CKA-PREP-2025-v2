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

NS=sidecars
DEP=legacy

echo "== v14: Convert a legacy sidecar into a native one =="

if ! exists "Deployment $DEP exists in namespace $NS" -n "$NS" deploy "$DEP"; then
  echo; echo -e "${R}v14 FAILED ($FAILS checks)${X}"; exit 1
fi

# Give the rollout a moment to settle, so that a Deployment applied a second
# ago is not failed for not having rolled out yet.
echo "Waiting for the rollout to settle..."
i=0
while [ "$i" -lt 30 ]; do
  READYREP=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [ "$READYREP" = "1" ] && break
  sleep 2
  i=$((i+2))
done

# ---- the logcollector has to be in spec.initContainers, as a sidecar ----
INIT_NAMES=$(k -n "$NS" get deploy "$DEP" \
             -o jsonpath='{range .spec.template.spec.initContainers[*]}{.name}{"\n"}{end}' 2>/dev/null \
             | tr -d '\r' | grep -v '^[[:space:]]*$')
if printf '%s\n' "$INIT_NAMES" | grep -qx 'logcollector'; then
  ok "spec.initContainers holds a container named logcollector"
else
  bad "spec.initContainers holds a container named logcollector (got: ${INIT_NAMES:-<none>})"
fi

INIT_RP=$(k -n "$NS" get deploy "$DEP" \
          -o jsonpath='{.spec.template.spec.initContainers[?(@.name=="logcollector")].restartPolicy}' 2>/dev/null)
eq "the logcollector init container has restartPolicy Always" "$INIT_RP" "Always"

# ---- and it must have MOVED, not been copied ----
CN=$(k -n "$NS" get deploy "$DEP" \
     -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{"\n"}{end}' 2>/dev/null \
     | tr -d '\r' | grep -v '^[[:space:]]*$')
COUNT=$(printf '%s\n' "$CN" | grep -c '[^[:space:]]')
eq "spec.containers holds only the app container" "$COUNT" "1"

if printf '%s\n' "$CN" | grep -qx 'app'; then
  ok "the container left in spec.containers is app"
else
  bad "the container left in spec.containers is app (got: ${CN:-<none>})"
fi

if printf '%s\n' "$CN" | grep -qx 'logcollector'; then
  bad "the logcollector was moved out of spec.containers (it is still there)"
else
  ok "the logcollector was moved out of spec.containers, not copied"
fi

# ---- the logcollector itself must be untouched ----
IMG=$(k -n "$NS" get deploy "$DEP" \
      -o jsonpath='{.spec.template.spec.initContainers[?(@.name=="logcollector")].image}' 2>/dev/null)
eq "the logcollector still uses busybox:1.36" "$IMG" "busybox:1.36"

CMD=$(k -n "$NS" get deploy "$DEP" \
      -o jsonpath='{.spec.template.spec.initContainers[?(@.name=="logcollector")].command}' 2>/dev/null)
nonempty "the logcollector still has a command" "$CMD"
has "the logcollector command still tails /var/log/app.log" "$CMD" "tail -f /var/log/app.log"

# ---- the shared volume ----
VNAMES=$(k -n "$NS" get deploy "$DEP" \
         -o jsonpath='{range .spec.template.spec.volumes[*]}{.name}{"\n"}{end}' 2>/dev/null \
         | tr -d '\r' | grep -v '^[[:space:]]*$')
has "the Deployment still has a volume named shared-logs" "$VNAMES" "shared-logs"

VOBJ=$(k -n "$NS" get deploy "$DEP" \
       -o jsonpath='{.spec.template.spec.volumes[?(@.name=="shared-logs")]}' 2>/dev/null)
has "the shared-logs volume is still an emptyDir" "$VOBJ" "emptyDir"

APPMP=$(k -n "$NS" get deploy "$DEP" \
        -o jsonpath='{.spec.template.spec.containers[?(@.name=="app")].volumeMounts[?(@.name=="shared-logs")].mountPath}' 2>/dev/null)
eq "the app container still mounts shared-logs at /var/log" "$APPMP" "/var/log"

SIDEMP=$(k -n "$NS" get deploy "$DEP" \
         -o jsonpath='{.spec.template.spec.initContainers[?(@.name=="logcollector")].volumeMounts[?(@.name=="shared-logs")].mountPath}' 2>/dev/null)
eq "the logcollector still mounts shared-logs at /var/log" "$SIDEMP" "/var/log"

# ---- the workload ----
REPLICAS=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.replicas}' 2>/dev/null)
UPDATED=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.updatedReplicas}' 2>/dev/null)
READYREP=$(k -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
eq "the Deployment has 1 ready replica" "$READYREP" "1"

if [ "$REPLICAS" = "1" ] && [ "$UPDATED" = "1" ]; then
  ok "the running pod is the one the current Deployment template describes"
else
  bad "the rollout finished on the current template (replicas '$REPLICAS', updated '$UPDATED', want 1 and 1)"
fi

POD=$(k -n "$NS" get pods -l "app=$DEP" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$POD" ]; then
  bad "a pod exists for the $DEP deployment"
  echo; echo -e "${R}v14 FAILED ($FAILS checks)${X}"; exit 1
fi
ok "the pod is $POD"

PHASE=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null)
eq "the pod is Running" "$PHASE" "Running"

# A native sidecar is reported under initContainerStatuses, an old-style
# sidecar under containerStatuses. Count both so the check works either way.
READY_NAMES=$( { k -n "$NS" get pod "$POD" -o jsonpath='{range .status.containerStatuses[*]}{.name}={.ready}{"\n"}{end}' 2>/dev/null
                 k -n "$NS" get pod "$POD" -o jsonpath='{range .status.initContainerStatuses[*]}{.name}={.ready}{"\n"}{end}' 2>/dev/null; } \
               | grep -E '^(app|logcollector)=true$' | sort -u )
READY_COUNT=$(printf '%s\n' "$READY_NAMES" | grep -c '[^[:space:]]')
eq "the pod has 2 ready containers (app and logcollector)" "$READY_COUNT" "2"

# ---- and the running pod really is the native one ----
PODRP=$(k -n "$NS" get pod "$POD" \
        -o jsonpath='{.spec.initContainers[?(@.name=="logcollector")].restartPolicy}' 2>/dev/null)
eq "the running pod's logcollector is a sidecar (restartPolicy Always)" "$PODRP" "Always"

PODCT=$(k -n "$NS" get pod "$POD" \
        -o jsonpath='{range .spec.containers[*]}{.name}{"\n"}{end}' 2>/dev/null \
        | tr -d '\r' | grep -v '^[[:space:]]*$')
PODCOUNT=$(printf '%s\n' "$PODCT" | grep -c '[^[:space:]]')
eq "the running pod has only the app container in spec.containers" "$PODCOUNT" "1"

note "A native sidecar starts before the main containers and is considered"
note "STARTED before the next init container and before the app runs, is"
note "restarted on its own if it crashes, and is terminated automatically once"
note "the pod's main containers have finished."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}v14 PASSED${X}"; else echo -e "${R}v14 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
