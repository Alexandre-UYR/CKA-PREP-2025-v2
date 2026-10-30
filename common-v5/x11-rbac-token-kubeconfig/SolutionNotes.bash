# 1. Grant the ServiceAccount exactly one thing: list on pods, in its own
#    namespace. A Role is namespaced, and so is the binding that follows.
kubectl -n rbac create role pod-lister --verb=list --resource=pods

kubectl -n rbac create rolebinding pod-lister \
  --role=pod-lister --serviceaccount=rbac:admin

# 2. Ask the API server what that ServiceAccount can do. The identity is
#    system:serviceaccount:<namespace>:<name>.
kubectl auth can-i list pods --as=system:serviceaccount:rbac:admin -n rbac
# yes
kubectl auth can-i list pods --as=system:serviceaccount:rbac:admin -n default
# no
#
# The RoleBinding is namespaced, so the second one is refused. That is the
# boundary the question is about.

# 3. Mint a token. Since Kubernetes 1.24 there are no long-lived token
#    Secrets for ServiceAccounts, so the token is created on demand and is
#    short-lived.
TOKEN=$(kubectl -n rbac create token admin --duration=1h)
echo "$TOKEN" | head -c 40
# eyJhbGciOiJSUzI1NiIsImtpZCI6IiJ9...

# 4. Build a kubeconfig of its own. The cluster and the certificate authority
#    are copied out of the current kubeconfig, because a context needs both
#    as well as credentials.
SERVER=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.server}')
CA=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

kubectl config set-cluster local \
  --server="$SERVER" \
  --certificate-authority-data="$CA" \
  --embed-certs=true \
  --kubeconfig=/root/rbac.kubeconfig

kubectl config set-credentials sa-admin \
  --token="$TOKEN" \
  --kubeconfig=/root/rbac.kubeconfig

kubectl config set-context rbac-admin \
  --cluster=local \
  --user=sa-admin \
  --namespace=rbac \
  --kubeconfig=/root/rbac.kubeconfig

kubectl config use-context rbac-admin --kubeconfig=/root/rbac.kubeconfig

# 5. Use it, which is what the task asks for.
kubectl --kubeconfig=/root/rbac.kubeconfig get pods -n rbac
# No resources found in rbac namespace.
#
# The command succeeds. With the admin's own kubeconfig it would also
# succeed, but here it is the ServiceAccount's token that the API server
# checks.

# 6. Prove the boundary with the same credentials.
kubectl --kubeconfig=/root/rbac.kubeconfig auth can-i list pods -n rbac
# yes
kubectl --kubeconfig=/root/rbac.kubeconfig auth can-i list pods -n default
# no

kubectl --kubeconfig=/root/rbac.kubeconfig get pods -n default
# Error from server (Forbidden): pods is forbidden: User
# "system:serviceaccount:rbac:admin" cannot list resource "pods" in API group
# "" in the namespace "default"
#
# The error names the ServiceAccount, which is the proof that the kubeconfig
# really is carrying its token and not the administrator's.
