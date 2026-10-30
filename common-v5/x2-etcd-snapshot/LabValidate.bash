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

LABDIR=/tmp/cka-lab
ENVFILE="$LABDIR/x2.env"

echo "== x2: Take a copy of the cluster's brain =="

# ---- what the setup recorded ------------------------------------------------

env_get(){
  sed -n "s/^$1=//p" "$ENVFILE" 2>/dev/null | head -n 1
}

TOOL=$(env_get TOOL)
ENDPOINT=$(env_get ENDPOINT)
CACERT=$(env_get CACERT)
CERT=$(env_get CERT)
KEY=$(env_get KEY)

# Fall back to what can be found on the machine right now, in case the state
# file is missing or the candidate installed a tool after the setup ran.
if [ -z "$TOOL" ]; then
  if command -v etcdutl >/dev/null 2>&1; then
    TOOL=etcdutl
  elif command -v etcdctl >/dev/null 2>&1; then
    TOOL=etcdctl
  fi
fi
if [ -z "$ENDPOINT" ]; then ENDPOINT="https://127.0.0.1:2379"; fi

# ---- the snapshot file ------------------------------------------------------

SNAP=""
for CAND in "$HOME/snapshotdb" "/root/snapshotdb"; do
  if [ -n "$CAND" ] && [ -f "$CAND" ]; then SNAP="$CAND"; break; fi
done

if [ -z "$SNAP" ]; then
  bad "the snapshot file ~/snapshotdb exists"
elif [ ! -s "$SNAP" ]; then
  bad "the snapshot file ~/snapshotdb is not empty (it is 0 bytes)"
else
  ok "the snapshot file ~/snapshotdb exists and is not empty"
fi

# ---- the snapshot really is a snapshot --------------------------------------

STATUS_OUT=""
STATUS_RC=1
if [ -n "$SNAP" ] && [ -s "$SNAP" ] && [ -n "$TOOL" ]; then
  if [ "$TOOL" = "etcdctl" ]; then
    STATUS_OUT=$(ETCDCTL_API=3 etcdctl snapshot status "$SNAP" 2>&1)
  else
    STATUS_OUT=$(etcdutl snapshot status "$SNAP" 2>&1)
  fi
  STATUS_RC=$?
  if [ "$STATUS_RC" -eq 0 ]; then
    ok "$TOOL snapshot status reads the file as a valid etcd snapshot"
  else
    bad "$TOOL snapshot status reads the file as a valid etcd snapshot (it failed: $(printf '%s' "$STATUS_OUT" | tr '\n' ' ' | cut -c1-200))"
  fi
elif [ -z "$TOOL" ]; then
  skip "etcdutl/etcdctl snapshot status (neither tool is installed on this node)"
else
  skip "$TOOL snapshot status (there is no snapshot file to read)"
fi

# ---- the revision count -----------------------------------------------------
# Only graded when the tool could read the file and reported a revision.

if [ "$STATUS_RC" -eq 0 ] && [ -n "$STATUS_OUT" ]; then
  REV=$(printf '%s' "$STATUS_OUT" \
        | tr 'A-Z' 'a-z' \
        | grep -i 'revision' \
        | tail -n 1 \
        | sed 's/.*revision[^0-9]*\([0-9][0-9]*\).*/\1/')
  if [ -z "$REV" ]; then
    note "The snapshot status output did not report a revision count."
  elif [ "$REV" -gt 0 ] 2>/dev/null; then
    ok "the snapshot reports a non-zero revision count (revision $REV)"
  else
    bad "the snapshot reports a non-zero revision count (got '$REV')"
  fi
elif [ -z "$TOOL" ]; then
  # Without a tool the file signature is the only evidence there is.
  if [ -n "$SNAP" ] && [ -s "$SNAP" ]; then
    MAGIC=$(od -An -tx1 -N4 "$SNAP" 2>/dev/null | tr -d ' \n')
    if [ "$MAGIC" = "edda0ced" ]; then
      ok "the file is an etcd snapshot (a bbolt database, signature ed da 0c ed)"
    elif grep -qa 'registry' "$SNAP" 2>/dev/null; then
      ok "the file is an etcd snapshot (it carries the cluster's registry keys)"
    else
      bad "the file is an etcd snapshot (it is not a bbolt database - an etcd snapshot starts with the bytes ed da 0c ed)"
    fi
  else
    skip "the file signature (there is no snapshot file to read)"
  fi
else
  skip "the snapshot's revision count (the snapshot could not be read)"
fi

# ---- the control plane was not stopped --------------------------------------

APICHECK=0
KUBEFLAGS=""
if command -v kubectl >/dev/null 2>&1; then
  for KC in "${KUBECONFIG:-}" /etc/kubernetes/admin.conf "$HOME/.kube/config"; do
    [ -n "$KC" ] || continue
    [ -r "$KC" ] || continue
    if kubectl --kubeconfig "$KC" get --raw /healthz >/dev/null 2>&1; then
      KUBEFLAGS="--kubeconfig $KC"
      APICHECK=1
      break
    fi
  done
  if [ "$APICHECK" -eq 0 ]; then
    if kubectl get --raw /healthz >/dev/null 2>&1; then
      APICHECK=1
    fi
  fi
fi

if [ "$APICHECK" -eq 1 ]; then
  HEALTH=$(kubectl $KUBEFLAGS get --raw /healthz 2>/dev/null | tr -d '\r\n')
  if [ "$HEALTH" = "ok" ]; then
    ok "the control plane was not stopped - the API server is still serving"
  else
    bad "the control plane was not stopped - the API server does not answer (healthz said '${HEALTH:-<nothing>}')"
  fi

  ETCDPHASE=$(kubectl $KUBEFLAGS -n kube-system get pods -l component=etcd \
                -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
  if [ "$ETCDPHASE" = "Running" ]; then
    ok "the etcd static pod is still Running"
  elif [ -z "$ETCDPHASE" ]; then
    skip "the etcd static pod is still Running (no etcd pod found in kube-system)"
  else
    bad "the etcd static pod is still Running (it is '$ETCDPHASE')"
  fi
else
  skip "the control plane was not stopped (kubectl could not reach the API server from this node)"
fi

note "etcd in a kubeadm cluster is a static pod, but its port is on the node -"
note "the snapshot is taken from the node, with the CA certificate and a client"
note "certificate and key, not through kubectl."
note "The endpoint recorded at setup was: $ENDPOINT"

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}x2 PASSED${X}"; else echo -e "${R}x2 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
