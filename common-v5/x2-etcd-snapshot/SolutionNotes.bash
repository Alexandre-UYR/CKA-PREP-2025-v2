# 1. You are on the control-plane node, so everything you need is here.
ls -l /etc/kubernetes/manifests/
# etcd.yaml
# kube-apiserver.yaml
# kube-controller-manager.yaml
# kube-scheduler.yaml
#
# etcd is a STATIC POD: its manifest lives on the node and the kubelet starts
# it. That does not stop you reaching it - it listens on a port on this node,
# and this node holds the certificates the port demands.

# 2. Find the endpoint etcd actually listens on.
grep listen-client-urls /etc/kubernetes/manifests/etcd.yaml
#     - --listen-client-urls=https://127.0.0.1:2379

# 3. Find the certificates. etcd is TLS-only, so all three are needed:
#    the CA to verify the server, and a client certificate and key to prove
#    that YOU are allowed in.
ls -l /etc/kubernetes/pki/etcd/
# apiserver-etcd-client.crt
# apiserver-etcd-client.key
# ca.crt
# ca.key
# healthcheck-client.crt
# healthcheck-client.key
# peer-ca.crt
# ...
#
# healthcheck-client and apiserver-etcd-client are both CLIENT pairs, signed
# by the etcd CA. Either one works. server.crt/server.key are the SERVER's own
# credentials - they are issued for server authentication and etcd will not
# accept them as a client.

# 4. Take the snapshot. etcdutl is the modern tool; etcdctl does the same job
#    with the v3 API.
etcdutl snapshot save ~/snapshotdb \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key
# Snapshot saved at /root/snapshotdb
#
# or, with etcdctl:
ETCDCTL_API=3 etcdctl snapshot save ~/snapshotdb \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key
# {"level":"info","msg":"created temporary db file",...}
# {"level":"info","msg":"saved","path":"/root/snapshotdb"}

# 5. Read the snapshot back. This is the check the grader makes.
etcdutl snapshot status ~/snapshotdb
# Hash:         8f3b...
# Revision:     142
# Total Key:    318
#
# or:
ETCDCTL_API=3 etcdctl snapshot status ~/snapshotdb
# Hash:      8f3b...
# Revision:  142
# Total Key: 318

# 6. Confirm the control plane is still up. It should be - a snapshot is a
#    read-and-copy, not a shutdown.
kubectl get nodes
# NAME       STATUS   ROLES           AGE   VERSION
# node1      Ready    control-plane   12h   v1.32.0

# A note on what did NOT work: stopping the etcd static pod to take the copy
# (it makes the cluster unavailable and it does not even help - the database
# is still locked by the running process), and pointing the client at the
# server certificate instead of a client certificate (etcd rejects it).
