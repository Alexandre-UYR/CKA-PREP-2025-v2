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

NS=reg
POD=app
CM=image-tags
LABDIR=/tmp/cka-lab

echo "== x18: The tag that does not exist =="

if ! exists "Pod $POD exists in namespace $NS" -n "$NS" pod "$POD"; then
  echo; echo -e "${R}x18 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the image the Pod is asking for ----
IMG=$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[0].image}' 2>/dev/null)
nonempty "the Pod names an image" "$IMG"

# Split the reference into repository and tag. A tag only exists if it is
# after the last colon and does not itself contain a slash (that would be a
# registry port, as in reg:5000/nginx).
REPO="$IMG"; TAG=""
case "$IMG" in
  *:*) TAG=${IMG##*:}; REPO=${IMG%:*};;
esac
case "$TAG" in
  */*) TAG=""; REPO="$IMG";;
esac
BASE=${REPO##*/}

# ---- is that tag one the ConfigMap actually lists? ----
# The lookup is against the live ConfigMap's data, not against a fixed list,
# so the answer follows whatever the ConfigMap says.
KEYS=$(k -n "$NS" get cm "$CM" -o go-template='{{range $k, $v := .data}}{{$k}}{{"\n"}}{{end}}' 2>/dev/null)
TAGOK=0
SEEN=""
for KEY in $KEYS; do
  VAL=$(k -n "$NS" get cm "$CM" -o go-template="{{index .data \"$KEY\"}}" 2>/dev/null)
  case "$BASE" in
    "$KEY") ;;
    *) continue;;
  esac
  for T in $VAL; do
    SEEN="$SEEN $KEY:$T"
    if [ "$T" = "$TAG" ]; then TAGOK=1; fi
  done
done

if [ -z "$KEYS" ]; then
  bad "the Pod's image tag is one the ConfigMap lists (the ConfigMap $CM is missing or empty)"
elif [ "$TAGOK" = "1" ]; then
  ok "the Pod's image tag '$TAG' is one the ConfigMap lists"
else
  bad "the Pod's image tag is one the ConfigMap lists (image '$IMG', tag '$TAG'; the ConfigMap lists:${SEEN:- <nothing>})"
fi

# ---- the Pod is up ----
# The image has to be pulled, so give it a moment.
PHASE=""
READY=""
WAITING=""
i=0
while [ "$i" -lt 120 ]; do
  PHASE=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null) || PHASE=""
  READY=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null) || READY=""
  WAITING=$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null) || WAITING=""
  if [ "$PHASE" = "Running" ] && [ "$READY" = "true" ] && [ -z "$WAITING" ]; then break; fi
  sleep 3
  i=$((i+3))
done

eq "the Pod is Running" "$PHASE" "Running"
eq "the container is ready" "$READY" "true"
if [ -z "$WAITING" ]; then
  ok "the container is no longer waiting"
else
  bad "the container is no longer waiting (it is waiting on '$WAITING')"
fi

# ---- and the ConfigMap was left alone ----
ORIG=$(cat "$LABDIR/x18.cm.data" 2>/dev/null || true)
LIVE=$(k -n "$NS" get cm "$CM" \
        -o go-template='{{range $k, $v := .data}}{{$k}}={{$v}}{{"\n"}}{{end}}' 2>/dev/null)
if [ -z "$ORIG" ]; then
  bad "the ConfigMap $CM is unchanged (no copy of it was taken at setup)"
elif [ "$ORIG" = "$LIVE" ]; then
  ok "the ConfigMap $CM is unchanged"
else
  bad "the ConfigMap $CM is unchanged (got '$LIVE', want '$ORIG')"
fi

note "ImagePullBackOff is the kubelet's RETRY state: the first failure shows"
note "up as ErrImagePull, and the back-off that follows shows as"
note "ImagePullBackOff. The events on the Pod say why the pull failed."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}x18 PASSED${X}"; else echo -e "${R}x18 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
