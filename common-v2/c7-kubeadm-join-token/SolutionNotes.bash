# c7 — Prepare a node join: the reference answer
#
# Run this on the control-plane node, as root.

# ------------------------------------------------------- 1. the API server ---

# The URL the joining node will use, with the scheme.
API=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
echo "$API"
# https://10.0.0.1:6443

# ----------------------------------------------------------- 2. the token ----

TOKEN=$(kubeadm token create)
echo "$TOKEN"
# a1b2c3.0123456789abcdef

# kubeadm can print the whole command itself, but it uses the advertise
# address (10.0.0.1:6443) rather than the https:// URL, so the command is
# assembled by hand below.
kubeadm token create --print-join-command
# kubeadm join 10.0.0.1:6443 --token a1b2c3.0123456789abcdef \
#   --discovery-token-ca-cert-hash sha256:abcdef...

# -------------------------------------------------- 3. the CA certificate ---

# The hash of the CA's public key, not of the certificate file.
CA=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt \
      | openssl rsa -pubin -outform der 2>/dev/null \
      | openssl dgst -sha256 -hex | sed 's/^.* //')
echo "$CA"
# sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef

# ------------------------------------------------ 4. write the join command --

cat <<EOF > /root/kubeadm-join.sh
kubeadm join ${API} --token ${TOKEN} --discovery-token-ca-cert-hash ${CA}
EOF

cat /root/kubeadm-join.sh
# kubeadm join https://10.0.0.1:6443 --token a1b2c3.0123456789abcdef \
#   --discovery-token-ca-cert-hash sha256:0123...

chmod 600 /root/kubeadm-join.sh

# ---------------------------------------------------- 5. show the token is good -

kubeadm token list
# TOKEN   TTL   EXPIRES   USAGES   DESCRIPTION   EXTRA GROUPS
# a1b2c3  2h    1h20m     1        the default token

# The token in the file is the one that was just created:
grep -oE '[a-z0-9]{6}\.[a-z0-9]{16}' /root/kubeadm-join.sh
# a1b2c3.0123456789abcdef

# ------------------------------------------------------- 6. clean up after ---

# The token lives in the API server until it is deleted:
kubeadm token delete a1b2c3
kubeadm token list
# TOKEN   TTL   EXPIRES   USAGES   DESCRIPTION   EXTRA GROUPS
# (empty)
