# 1. Apply the Issuer manifest the setup left behind.
#
#    kubectl apply -f /tmp/cka-lab/issuer.yaml
#
#    That is a self-signed Issuer named `selfsigned` in the `pki` namespace:
#
#    apiVersion: cert-manager.io/v1
#    kind: Issuer
#    metadata:
#      name: selfsigned
#      namespace: pki
#    spec:
#      selfSigned: {}
#
#    Check that it is Ready:
#
#    kubectl -n pki get issuer
#    NAME         READY   AGE
#    selfsigned   True    2s
#
#    An Issuer is the authority that signs. A self-signed Issuer is its own
#    authority: it makes a key pair, signs a certificate with it, and keeps
#    the key pair in a Secret in its own namespace.

# 2. Create the Certificate.
cat <<'EOF' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-cert
  namespace: pki
spec:
  issuerRef:
    name: selfsigned
  commonName: example.com
  dnsNames:
    - example.com
  secretName: test
EOF

# 3. Look at the Certificate. This is a REQUEST - it says what is wanted,
#    it is not the certificate.
kubectl -n pki get certificate test-cert
# NAME        READY   SECRET   AGE
# test-cert   True    test     3s
#
# The status carries the conditions, and says what the controller is doing:
kubectl -n pki get certificate test-cert -o yaml | sed -n '/^status:/,$p'

# 4. The evidence is the Secret. The controller created it and put the
#    signed certificate in tls.crt and the private key in tls.key.
kubectl -n pki get secret test
# NAME   TYPE     DATA   AGE
# test   Opaque   2      3s

kubectl -n pki get secret test -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject -issuer -dates
# subject=CN = example.com
# issuer=CN = example.com
# notBefore=Oct 30 10:00:00 2026 GMT
# notAfter=Oct 30 10:00:00 2027 GMT
#
# The issuer is the Issuer itself: that is what a self-signed certificate
# looks like.

# 5. And the certificate really is in there, in PEM form:
kubectl -n pki get secret test -o jsonpath='{.data.tls\.crt}' | base64 -d
# -----BEGIN CERTIFICATE-----
# MIIDazCCAlOgAwIBAgIUZ7bq...
# -----END CERTIFICATE-----

# If nothing happens, the controller is not reconciling the Certificate.
# Look at it:
kubectl -n cert-manager get pods
kubectl -n cert-manager logs deploy/cert-manager --tail=30
#
# The Certificate's own status usually says why as well: a Certificate that
# is stuck with `Reason: DoesNotExist` is waiting for an Issuer that is not
# there, and one with `Reason: Failed` names the problem in its message.
