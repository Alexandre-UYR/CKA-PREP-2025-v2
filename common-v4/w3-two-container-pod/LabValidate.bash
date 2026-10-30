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

NS=multi
DEP=single
POD=multi-pod

echo "== w3: A Pod with two containers =="

# The number of seconds passed to sleep, read out of a container's command and
# args. Prints nothing when there is no sleep in there.
sleep_value(){
  local line="$1" prev="" tok
  for tok in $line; do
    case "$prev" in
      sleep|*/sleep)
        case "$tok" in
          ''|*[!0-9]*) ;;
          *) echo "$tok"; return 0 ;;
        esac
        ;;
    esac
    prev="$tok"
  done
  return 1
}

# The command and args of one container, flattened into one line.
cmd_line(){
  local idx="$1" raw args
  raw=$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.containers[$idx].command}" 2>/dev/null || true)
  args=$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.containers[$idx].args}" 2>/dev/null || true)
  printf '%s %s' "$raw" "$args" | tr -d '[]",'
}

# ---- the pre-state ---------------------------------------------------------

exists "Deployment $DEP exists in namespace $NS" -n "$NS" deploy "$DEP"

# ---- the Pod itself --------------------------------------------------------

if ! exists "Pod $POD exists in namespace $NS" -n "$NS" pod "$POD"; then
  echo; echo -e "${R}w3 FAILED ($FAILS checks)${X}"; exit 1
fi

eq "the Pod's phase is Running" \
  "$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null)" "Running"

eq "the Pod carries the label env=test" \
  "$(k -n "$NS" get pod "$POD" -o jsonpath='{.metadata.labels.env}' 2>/dev/null)" "test"

# ---- 1. exactly two containers, named busy1 and busy2 -----------------------

NAMES=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null || true)
COUNT=$(printf '%s' "$NAMES" | wc -w | tr -d ' ')
eq "the Pod has exactly two containers" "$COUNT" "2"

has "the Pod has a container named busy1" "$NAMES" "busy1"
has "the Pod has a container named busy2" "$NAMES" "busy2"

# The image of each container, matched by name rather than by position.
IMAGES=$(k -n "$NS" get pod "$POD" \
           -o go-template='{{range .spec.containers}}{{.name}}={{.image}}{{"\n"}}{{end}}' 2>/dev/null || true)
for c in busy1 busy2; do
  IMG=""
  for row in $IMAGES; do
    case "$row" in
      "$c"=*) IMG="${row#*=}" ;;
    esac
  done
  case "$IMG" in
    *busybox:1.36*)
      ok "container $c uses busybox:1.36" ;;
    busybox*)
      bad "container $c uses busybox:1.36 (its image is '$IMG')" ;;
    *)
      bad "container $c uses busybox:1.36 (its image is '$IMG')" ;;
  esac
done

# ---- 2. both commands sleep for at least 100000 seconds --------------------

idx=0
while [ "$idx" -lt 2 ]; do
  cname=$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.containers[$idx].name}" 2>/dev/null || true)
  line=$(cmd_line "$idx")
  sv=$(sleep_value "$line")
  if [ -n "$sv" ] && [ "$sv" -ge 100000 ]; then
    ok "container ${cname:-#$idx} sleeps for $sv seconds (100000 or more)"
  else
    bad "container ${cname:-#$idx} sleeps for 100000 seconds or more (its command is '$line')"
  fi
  idx=$((idx+1))
done

# ---- 4. both containers are Ready, and neither has restarted ---------------

STATUS=$(k -n "$NS" get pod "$POD" \
           -o go-template='{{range .status.containerStatuses}}{{.name}}|{{.ready}}|{{.restartCount}}{{"\n"}}{{end}}' 2>/dev/null || true)

for c in busy1 busy2; do
  ready=""
  restarts=""
  for row in $STATUS; do
    case "$row" in
      "$c"\|*) ready=$(printf '%s' "$row" | cut -d'|' -f2); restarts=$(printf '%s' "$row" | cut -d'|' -f3) ;;
    esac
  done
  if [ "$ready" = "true" ]; then
    ok "container $c is Ready"
  else
    bad "container $c is Ready (got '$ready')"
  fi
  eq "container $c has not restarted" "$restarts" "0"
done

note "A Pod with two containers shares one network namespace and one"
note "lifecycle: if one container exits, the Pod is restarted as a whole."
note "That is why both commands have to be long-running, and why the"
note "restart count is checked as well as the phase."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}w3 PASSED${X}"; else echo -e "${R}w3 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
