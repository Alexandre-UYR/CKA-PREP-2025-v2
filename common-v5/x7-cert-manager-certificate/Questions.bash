# Question: A certificate, issued
#
# cert-manager is installed and there is an Issuer manifest waiting at
# /tmp/cka-lab/issuer.yaml.
#
# Task:
# 1. Apply it to create the Issuer `selfsigned` in the `pki` namespace.
# 2. Create a Certificate `test-cert` in the `pki` namespace that uses that
#    Issuer:
#    - commonName: example.com
#    - dnsNames: [example.com]
#    - secretName: test
#
# cert-manager will issue the certificate and store it in a Secret named
# `test`.
#
# Prove it: the Secret exists and holds a certificate.
