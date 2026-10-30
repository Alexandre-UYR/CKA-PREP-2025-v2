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

# Convert an RFC3339 timestamp to epoch seconds. GNU date first, BSD date second.
to_epoch(){
  local ts="$1"
  [ -n "$ts" ] || return 1
  if date -d "$ts" +%s >/dev/null 2>&1; then date -d "$ts" +%s; return 0; fi
  if date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s >/dev/null 2>&1; then date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s; return 0; fi
  return 1
}

# Can this machine open a TCP connection to host:port?
tcp_open(){
  local host="$1" port="$2"
  if command -v timeout >/dev/null 2>&1; then
    timeout 5 bash -c "exec 3<>/dev/tcp/${host}/${port}" >/dev/null 2>&1 && return 0
  else
    (exec 3<>"/dev/tcp/${host}/${port}") >/dev/null 2>&1 && return 0
  fi
  return 1
}

echo "== Q17 TLS Config =="

NS=nginx-static
HOSTNAME_ENTRY=ckaquestion.k8s.local

# ---- 1. the ConfigMap now only allows TLSv1.3 ----
CONF=$(k -n "$NS" get cm nginx-config -o jsonpath='{.data.nginx\.conf}' 2>/dev/null)
has "the ConfigMap nginx-config's nginx.conf enables TLSv1.3" "$CONF" "TLSv1.3"

case "$CONF" in
  *TLSv1.2*)
    bad "the ConfigMap nginx-config's nginx.conf still contains TLSv1.2 (want TLSv1.3 only)";;
  *)
    ok "the ConfigMap nginx-config's nginx.conf no longer contains TLSv1.2";;
esac

# ---- 2. the pods must have been restarted to pick the new config up ----
# Editing a ConfigMap does not restart the pods that mount it: the file is a
# projection that is refreshed in the running container, but nginx only reads
# its configuration at start-up. So the pod has to be newer than the original.
OLD_RAW=$(cat /tmp/cka-lab/q17.pod.before 2>/dev/null)
CUR_RAW=$(k -n "$NS" get pods -l app=nginx-static -o jsonpath='{range .items[*]}{.metadata.creationTimestamp}{"\n"}{end}' 2>/dev/null \
          | grep -v '^$' | sort | tail -1)

if [ -z "$CUR_RAW" ]; then
  bad "there is no nginx-static pod running, so the ConfigMap could not be applied to it"
else
  OLD_E=$(to_epoch "$OLD_RAW" 2>/dev/null || true)
  CUR_E=$(to_epoch "$CUR_RAW" 2>/dev/null || true)
  NEWER=0
  if [ -n "$OLD_RAW" ] && [ -n "$OLD_E" ] && [ -n "$CUR_E" ]; then
    [ "$CUR_E" -gt "$OLD_E" ] && NEWER=1
  elif [ -n "$OLD_RAW" ]; then
    # fall back to a plain string comparison of the two RFC3339 timestamps
    [ "$CUR_RAW" \> "$OLD_RAW" ] && NEWER=1
  else
    SETUP_TS=$(cat /tmp/cka-lab/q17.setup.time 2>/dev/null)
    if [ -n "$SETUP_TS" ] && [ -n "$CUR_E" ]; then
      [ "$CUR_E" -gt "$SETUP_TS" ] && NEWER=1
      OLD_RAW="(the lab finished setting up at epoch $SETUP_TS)"
    fi
  fi

  if [ "$NEWER" -eq 1 ]; then
    ok "the nginx-static pod was recreated after the ConfigMap was changed (it now runs the new config)"
  elif [ -n "$OLD_RAW" ]; then
    bad "the nginx-static pod was NOT restarted (pod creationTimestamp '$CUR_RAW' is not newer than the original '$OLD_RAW') - editing a ConfigMap does not restart the pods that mount it, so the running nginx is still using the old ssl_protocols"
  else
    skip "no record of the original pod was kept, so the pod-restart check could not be run"
  fi
fi

# ---- 3. the deployment is still healthy ----
READY=""
for _ in $(seq 1 30); do
  READY=$(k -n "$NS" get deploy nginx-static -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [ "$READY" = "1" ] && break
  sleep 2
done
eq "the nginx-static deployment still has 1 ready replica" "$READY" "1"

# ---- 4. /etc/hosts points ckaquestion.k8s.local at the Service ----
HOSTS_TXT=""
if [ -r /etc/hosts ]; then
  HOSTS_TXT=$(cat /etc/hosts 2>/dev/null)
elif sudo -n cat /etc/hosts >/dev/null 2>&1; then
  HOSTS_TXT=$(sudo -n cat /etc/hosts 2>/dev/null)
else
  HOSTS_TXT=""
fi

if [ -z "$HOSTS_TXT" ]; then
  bad "/etc/hosts could not be read - run the validator with permission to read it (try sudo)"
  HOSTIP=""
else
  HOSTIP=$(printf '%s\n' "$HOSTS_TXT" | awk -v n="$HOSTNAME_ENTRY" '$0 ~ n { print $1; exit }')
  nonempty "/etc/hosts has an entry for $HOSTNAME_ENTRY" "$HOSTIP"
fi

CIP=$(k -n "$NS" get svc nginx-service -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
nonempty "the nginx-service Service in $NS has a ClusterIP" "$CIP"

if [ -n "$HOSTIP" ] && [ -n "$CIP" ]; then
  eq "the /etc/hosts entry for $HOSTNAME_ENTRY points at the nginx-service ClusterIP" "$HOSTIP" "$CIP"
fi

# ---- 5. the TLS behaviour itself ----
echo
echo "Testing the TLS behaviour of $HOSTNAME_ENTRY..."
if ! curl --tlsv1.3 --version >/dev/null 2>&1 || ! curl --tls-max 1.2 --version >/dev/null 2>&1; then
  skip "this build of curl does not support --tlsv1.3 / --tls-max, so the TLS version checks could not be run"
elif [ -z "$CIP" ] || ! tcp_open "$CIP" 443; then
  skip "this machine cannot open a TCP connection to ${CIP:-<no ClusterIP>}:443, so the TLS handshake could not be tested here"
else
  # TLS 1.3 first: if it does not work, the TLS 1.2 result cannot be interpreted.
  T13=$(curl -vk --tlsv1.3 --connect-timeout 5 -o /dev/null -w "%{http_code}" \
          "https://${HOSTNAME_ENTRY}" 2>&1)
  RC13=$?
  if [ "$RC13" -eq 0 ]; then
    ok "TLS 1.3 works against $HOSTNAME_ENTRY (curl exited 0, HTTP $T13)"
    T13OK=1
  else
    bad "TLS 1.3 did NOT work against $HOSTNAME_ENTRY (curl exit $RC13): $(printf '%s' "$T13" | tr '\n' ' ' | tail -c 220)"
    T13OK=0
  fi

  T12=$(curl -vk --tls-max 1.2 --connect-timeout 5 -o /dev/null -w "%{http_code}" \
          "https://${HOSTNAME_ENTRY}" 2>&1)
  RC12=$?
  if [ "$RC12" -eq 0 ]; then
    bad "TLS 1.2 still works against $HOSTNAME_ENTRY (curl exited 0, HTTP $T12) - the server is still accepting TLSv1.2"
  elif [ "$T13OK" -eq 1 ]; then
    ok "TLS 1.2 is refused by $HOSTNAME_ENTRY (curl exit $RC12, the handshake was rejected)"
  else
    skip "TLS 1.3 also failed, so the TLS 1.2 result cannot be interpreted - this is the same failure as the TLS 1.3 check above, not a separate TLS 1.2 result"
  fi
fi

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}Q17 PASSED${X}"; else echo -e "${R}Q17 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
