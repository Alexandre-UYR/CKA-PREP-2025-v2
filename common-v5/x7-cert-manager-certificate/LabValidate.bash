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

NS=pki
CERT=test-cert
ISSUER=selfsigned
SECRET=test

echo "== x7: A certificate, issued =="

if ! exists "namespace $NS exists" namespace "$NS"; then
  echo; echo -e "${R}x7 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the environment has to be able to hold a Certificate at all ----
if ! exists "the cert-manager Certificate CRD is installed" crd certificates.cert-manager.io; then
  echo "      the cert-manager CRDs are not installed on this cluster, so there is"
  echo "      no Certificate kind to create and this question cannot be graded."
  echo "      Install cert-manager (or re-run the setup with network access) first."
  echo
  echo -e "${R}x7 FAILED ($FAILS checks)${X}"; exit 1
fi

# ---- the Issuer ----
if exists "Issuer $ISSUER exists in namespace $NS" -n "$NS" issuer "$ISSUER"; then
  READY=""
  i=0
  while [ "$i" -lt 15 ]; do
    READY=$(k -n "$NS" get issuer "$ISSUER" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    [ "$READY" = "True" ] && break
    i=$((i+1)); sleep 2
  done
  eq "the Issuer $ISSUER is Ready" "$READY" "True"
else
  bad "Issuer $ISSUER exists in namespace $NS"
fi

# ---- the Certificate ----
if exists "Certificate $CERT exists in namespace $NS" -n "$NS" certificate "$CERT"; then
  IREF=$(k -n "$NS" get certificate "$CERT" -o jsonpath='{.spec.issuerRef.name}' 2>/dev/null)
  eq "the Certificate's issuerRef.name is $ISSUER" "$IREF" "$ISSUER"

  CN=$(k -n "$NS" get certificate "$CERT" -o jsonpath='{.spec.commonName}' 2>/dev/null)
  eq "the Certificate's commonName is example.com" "$CN" "example.com"

  DNS=$(k -n "$NS" get certificate "$CERT" -o jsonpath='{.spec.dnsNames}' 2>/dev/null)
  has "the Certificate's dnsNames contains example.com" "$DNS" "example.com"

  SN=$(k -n "$NS" get certificate "$CERT" -o jsonpath='{.spec.secretName}' 2>/dev/null)
  eq "the Certificate's secretName is $SECRET" "$SN" "$SECRET"

  CREADY=$(k -n "$NS" get certificate "$CERT" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  if [ "$CREADY" = "True" ]; then
    ok "the Certificate reports Ready"
  else
    note "the Certificate's Ready condition is '${CREADY:-<none>}' - the controller may still be working"
  fi
else
  bad "Certificate $CERT exists in namespace $NS"
  CN=""; DNS=""; IREF=""; SN=""
fi

# ---- the Secret: the controller's output, and the real evidence ----
# The controller writes the Secret a moment after the Certificate is created,
# so give it time before deciding that it is not there.
B64=""
i=0
while [ "$i" -lt 30 ]; do
  B64=$(k -n "$NS" get secret "$SECRET" -o jsonpath='{.data.tls\.crt}' 2>/dev/null)
  [ -n "$B64" ] && break
  i=$((i+1)); sleep 2
done

if exists "Secret $SECRET exists in namespace $NS" -n "$NS" secret "$SECRET"; then
  nonempty "the Secret $SECRET holds a certificate (tls.crt is not empty)" "$B64"
else
  bad "Secret $SECRET exists in namespace $NS"
fi

# ---- and the certificate in it is for example.com ----
if [ -n "$B64" ]; then
  TMP=$(mktemp "${TMPDIR:-/tmp}/cka-x7.XXXXXX" 2>/dev/null || echo "/tmp/cka-x7.$$")
  printf '%s' "$B64" | base64 -D > "$TMP" 2>/dev/null
  [ -s "$TMP" ] || printf '%s' "$B64" | base64 -d > "$TMP" 2>/dev/null
  [ -s "$TMP" ] || printf '%s' "$B64" | openssl base64 -d -A > "$TMP" 2>/dev/null

  SUBJ=""
  if command -v openssl >/dev/null 2>&1; then
    SUBJ=$(openssl x509 -in "$TMP" -noout -subject 2>/dev/null | tr -d '\r\n')
  fi
  if [ -n "$SUBJ" ]; then
    has "the certificate in the Secret has example.com as its subject" "$SUBJ" "example.com"
  else
    # No openssl: decode the PEM body once more and look for the name in the
    # DER that comes out of it.
    BODY=$(grep -v -- '-----' "$TMP" 2>/dev/null | tr -d '\n \t\r')
    if printf '%s' "$BODY" | base64 -D 2>/dev/null | grep -a -q 'example.com'; then
      ok "the certificate in the Secret has example.com as its subject"
    elif printf '%s' "$BODY" | base64 -d 2>/dev/null | grep -a -q 'example.com'; then
      ok "the certificate in the Secret has example.com as its subject"
    else
      bad "the certificate in the Secret has example.com as its subject (the decoded certificate does not contain it)"
    fi
  fi
  rm -f "$TMP"
else
  bad "the certificate in the Secret has example.com as its subject (there is no tls.crt to decode)"
fi

note "A Certificate is a request. The controller reads it, does the work, and"
note "writes the issued certificate into the Secret - so the Secret, and not"
note "the Certificate object, is what proves the certificate was issued."

echo
if [ "$FAILS" -eq 0 ]; then echo -e "${G}x7 PASSED${X}"; else echo -e "${R}x7 FAILED ($FAILS checks)${X}"; fi
exit $(( FAILS > 0 ))
