#!/bin/bash
set -e

# x2 - Take a copy of the cluster's brain
#
# This is a NODE-level question: it is run on the control-plane node of a
# kubeadm cluster, not through kubectl.
#
# In a kubeadm cluster etcd is a STATIC POD: a pod whose manifest lives on the
# node (/etc/kubernetes/manifests/etcd.yaml) and which the kubelet starts and
# keeps. Static does not mean unreachable - etcd listens on a port on the node
# itself, and the node holds the PKI that the port demands, so the snapshot
# is taken from the node.
#
# The setup does NOT take the snapshot. It finds the endpoint and the
# certificates, records them so the grader uses exactly the same values, and
# checks that a snapshot tool is installed. If neither etcdctl nor etcdutl is
# on PATH the setup says so and still exits 0 - the snapshot file is still
# graded, only the tool-backed checks are skipped.

LABDIR=/tmp/cka-lab
PKI=/etc/kubernetes/pki/etcd
MANIFEST=/etc/kubernetes/manifests/etcd.yaml
ENVFILE="$LABDIR/x2.env"

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

mkdir -p "$LABDIR"

# ---- the snapshot tool ------------------------------------------------------
# etcdutl is the modern tool; etcdctl does the same job with the v3 API.

TOOL=""
if command -v etcdutl >/dev/null 2>&1; then
  TOOL=etcdutl
elif command -v etcdctl >/dev/null 2>&1; then
  TOOL=etcdctl
fi

# ---- the endpoint etcd listens on -------------------------------------------
# Read it out of the static pod's manifest rather than assuming it.

ENDPOINT=""
if [ -f "$MANIFEST" ]; then
  URLS=$(grep -o -- '--listen-client-urls=[^ "]*' "$MANIFEST" 2>/dev/null \
        | head -n 1 | cut -d= -f2- | tr -d "\"'" || true)
  case "$URLS" in
    https://*|http://*) ENDPOINT="$URLS";;
  esac
fi
if [ -z "$ENDPOINT" ]; then
  ENDPOINT="https://127.0.0.1:2379"
fi

# ---- the certificates -------------------------------------------------------

CACERT=""
if [ -f "$PKI/ca.crt" ]; then
  CACERT="$PKI/ca.crt"
fi

# A CLIENT certificate and key, signed by the etcd CA. kubeadm ships two such
# pairs; either is accepted by etcd for client authentication.
CERT=""
KEY=""
for PAIR in healthcheck-client apiserver-etcd-client; do
  if [ -f "$PKI/$PAIR.crt" ] && [ -f "$PKI/$PAIR.key" ]; then
    CERT="$PKI/$PAIR.crt"
    KEY="$PKI/$PAIR.key"
    break
  fi
done

# ---- record what the grader must use ---------------------------------------

{
  printf 'TOOL=%s\n' "$TOOL"
  printf 'ENDPOINT=%s\n' "$ENDPOINT"
  printf 'CACERT=%s\n' "$CACERT"
  printf 'CERT=%s\n' "$CERT"
  printf 'KEY=%s\n' "$KEY"
  printf 'MANIFEST=%s\n' "$MANIFEST"
  printf 'PKI=%s\n' "$PKI"
} > "$ENVFILE"

# ---- report -----------------------------------------------------------------

echo "x2 environment ready"
echo "   - this is a NODE-level question: run it on the control-plane node"
echo "   - etcd static pod manifest: $MANIFEST"
if [ -f "$MANIFEST" ]; then
  echo "     (present)"
else
  echo "     (NOT present - is this really the control-plane node?)"
fi
echo "   - etcd endpoint: $ENDPOINT"
echo "   - CA certificate: ${CACERT:-<not found>}"
echo "   - client certificate: ${CERT:-<not found>}"
echo "   - client key: ${KEY:-<not found>}"
echo "   - snapshot tool: ${TOOL:-<neither etcdctl nor etcdutl is on PATH>}"
echo "   - recorded in: $ENVFILE"

if [ -z "$TOOL" ]; then
  echo
  echo "⚠️  No snapshot tool is installed on this node." >&2
  echo "    Install one of them before you start:" >&2
  echo "      - download etcdutl or etcdctl from the etcd release page" >&2
  echo "        (https://github.com/etcd-io/etcd/releases) and put it on PATH" >&2
  echo "      - or copy the etcd binary out of the static pod's image:" >&2
  echo "        sudo crictl images | grep etcd" >&2
  echo "        sudo crictl run --rm -t <image> etcdutl version" >&2
  echo "    The lab still runs: the snapshot file is graded either way, and the" >&2
  echo "    tool-backed checks are skipped if the tool is still missing." >&2
fi

if [ -z "$CERT" ] || [ -z "$CACERT" ]; then
  echo
  echo "⚠️  The etcd PKI is incomplete under $PKI." >&2
  echo "    Without a CA certificate and a client certificate and key, etcd" >&2
  echo "    cannot be reached at all - it is TLS-only." >&2
fi

echo "   - Task: take a snapshot of the etcd database and save it as ~/snapshotdb"
